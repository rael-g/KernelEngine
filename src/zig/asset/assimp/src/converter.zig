const std = @import("std");

const c = @import("c.zig").c;
const log = @import("log.zig");

/// Returns the directory part of `path`, including the trailing separator, or
/// an empty slice when the path has none.
pub fn directoryOf(path: []const u8) []const u8 {
    const slash = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return "";
    return path[0 .. slash + 1];
}

fn hasNormals(am: *const c.aiMesh) bool {
    return am.mNormals != null;
}

fn hasUVs(am: *const c.aiMesh) bool {
    return am.mTextureCoords[0] != null;
}

fn hasTangents(am: *const c.aiMesh) bool {
    return am.mTangents != null and am.mBitangents != null;
}

/// Builds a tangent perpendicular to `n` for meshes that carry none: cross with
/// world-up, falling back to world-forward when the normal is near-vertical.
fn fallbackTangent(nx: f32, ny: f32, nz: f32) [3]f32 {
    var ux: f32 = 0;
    var uy: f32 = 1;
    var uz: f32 = 0;
    const dot_up = nx * ux + ny * uy + nz * uz;
    if (dot_up > 0.9 or dot_up < -0.9) {
        ux = 0;
        uy = 0;
        uz = 1;
    }
    const d = nx * ux + ny * uy + nz * uz;
    var tx = ux - nx * d;
    var ty = uy - ny * d;
    var tz = uz - nz * d;
    const len = @sqrt(tx * tx + ty * ty + tz * tz);
    if (len > 1e-4) {
        tx /= len;
        ty /= len;
        tz /= len;
    } else {
        tx = 1;
        ty = 0;
        tz = 0;
    }
    return .{ tx, ty, tz };
}

/// Releases the buffers `convertMesh` attached to `md`. Both counts on the
/// record are the exact allocation lengths, which is what the allocator needs
/// to match the block — see the shrink at the end of `convertMesh`.
pub fn freeMesh(gpa: std.mem.Allocator, md: *const c.ke_mesh_data) void {
    if (md.vertices) |v| gpa.free(v[0..md.vertex_count]);
    if (md.indices) |i| gpa.free(i[0..md.index_count]);
}

pub fn convertMesh(gpa: std.mem.Allocator, am: *const c.aiMesh, md: *c.ke_mesh_data) bool {
    md.* = std.mem.zeroes(c.ke_mesh_data);
    log.copyString(&md.name, &am.mName.data);
    md.vertex_count = am.mNumVertices;

    var index_count: usize = 0;
    for (0..am.mNumFaces) |fi| index_count += @min(3, am.mFaces[fi].mNumIndices);

    const vertices = gpa.alloc(c.ke_vertex, am.mNumVertices) catch return false;
    const indices = gpa.alloc(u16, index_count) catch {
        gpa.free(vertices);
        return false;
    };
    md.vertices = vertices.ptr;
    md.indices = indices.ptr;

    for (0..am.mNumVertices) |vi| {
        const v = &vertices[vi];
        v.* = std.mem.zeroes(c.ke_vertex);
        v.x = am.mVertices[vi].x;
        v.y = am.mVertices[vi].y;
        v.z = am.mVertices[vi].z;

        if (hasNormals(am)) {
            v.nx = am.mNormals[vi].x;
            v.ny = am.mNormals[vi].y;
            v.nz = am.mNormals[vi].z;
        } else {
            v.nx = 0;
            v.ny = 0;
            v.nz = 1;
        }

        if (hasUVs(am)) {
            v.u = am.mTextureCoords[0][vi].x;
            v.v = am.mTextureCoords[0][vi].y;
        }

        if (hasTangents(am)) {
            const t = am.mTangents[vi];
            const bt = am.mBitangents[vi];
            const n = am.mNormals[vi];
            v.tx = t.x;
            v.ty = t.y;
            v.tz = t.z;
            const cx = n.y * t.z - n.z * t.y;
            const cy = n.z * t.x - n.x * t.z;
            const cz = n.x * t.y - n.y * t.x;
            v.tw = if (cx * bt.x + cy * bt.y + cz * bt.z >= 0) 1 else -1;
        } else {
            const t = fallbackTangent(v.nx, v.ny, v.nz);
            v.tx = t[0];
            v.ty = t[1];
            v.tz = t[2];
            v.tw = 1;
        }
    }

    var cursor: usize = 0;
    for (0..am.mNumFaces) |fi| {
        const face = am.mFaces[fi];
        var j: u32 = 0;
        while (j < 3 and j < face.mNumIndices) : (j += 1) {
            indices[cursor] = @truncate(face.mIndices[j]);
            cursor += 1;
        }
    }
    md.index_count = @intCast(cursor);
    return true;
}

/// Assimp's AI_MATKEY_* macros are comma-separated (key, type, index) triples
/// rather than values, so translate-c cannot expand them into call arguments.
/// They are spelled out here against the same strings material.h defines.
const MatKey = struct {
    key: [*:0]const u8,
    type: c_uint = 0,
    index: c_uint = 0,

    const name: MatKey = .{ .key = "?mat.name" };
    const base_color: MatKey = .{ .key = "$clr.base" };
    const color_diffuse: MatKey = .{ .key = "$clr.diffuse" };
    const metallic_factor: MatKey = .{ .key = "$mat.metallicFactor" };
    const roughness_factor: MatKey = .{ .key = "$mat.roughnessFactor" };
};

fn getColor(am: *const c.aiMaterial, k: MatKey, out: *c.aiColor4D) bool {
    return c.aiGetMaterialColor(am, k.key, k.type, k.index, out) == c.aiReturn_SUCCESS;
}

fn getFloat(am: *const c.aiMaterial, k: MatKey, out: *f32) bool {
    return c.aiGetMaterialFloatArray(am, k.key, k.type, k.index, out, null) == c.aiReturn_SUCCESS;
}

pub fn convertMaterial(am: *const c.aiMaterial, md: *c.ke_material_data) void {
    md.* = std.mem.zeroes(c.ke_material_data);

    var name: c.aiString = undefined;
    const k = MatKey.name;
    if (c.aiGetMaterialString(am, k.key, k.type, k.index, &name) == c.aiReturn_SUCCESS) {
        log.copyString(&md.name, &name.data);
    }

    var color = c.aiColor4D{ .r = 1, .g = 1, .b = 1, .a = 1 };
    if (!getColor(am, MatKey.base_color, &color)) {
        _ = getColor(am, MatKey.color_diffuse, &color);
    }
    md.base_color_r = color.r;
    md.base_color_g = color.g;
    md.base_color_b = color.b;
    md.base_color_a = color.a;

    var metallic: f32 = 0.0;
    var roughness: f32 = 0.5;
    _ = getFloat(am, MatKey.metallic_factor, &metallic);
    _ = getFloat(am, MatKey.roughness_factor, &roughness);
    md.metallic = metallic;
    md.roughness = roughness;
}

const testing = std.testing;

const converter = @This();

fn aiStr(text: []const u8) c.aiString {
    var s: c.aiString = std.mem.zeroes(c.aiString);
    s.length = @intCast(text.len);
    @memcpy(s.data[0..text.len], text);
    return s;
}

fn prop(key: []const u8, ty: c_uint, data: []u8) c.aiMaterialProperty {
    var p: c.aiMaterialProperty = std.mem.zeroes(c.aiMaterialProperty);
    p.mKey = aiStr(key);
    p.mSemantic = 0;
    p.mIndex = 0;
    p.mType = ty;
    p.mDataLength = @intCast(data.len);
    p.mData = data.ptr;
    return p;
}

fn bytesOf(comptime T: type, value: *const T) []u8 {
    return @constCast(std.mem.asBytes(value));
}

const MaterialFixture = struct {
    mat: c.aiMaterial,
    props: [8]c.aiMaterialProperty,
    ptrs: [8][*c]c.aiMaterialProperty,
    count: usize = 0,

    fn init(self: *MaterialFixture) void {
        self.* = .{
            .mat = std.mem.zeroes(c.aiMaterial),
            .props = undefined,
            .ptrs = undefined,
            .count = 0,
        };
    }

    fn add(self: *MaterialFixture, p: c.aiMaterialProperty) void {
        self.props[self.count] = p;
        self.count += 1;
        for (0..self.count) |i| self.ptrs[i] = &self.props[i];
        self.mat.mProperties = &self.ptrs;
        self.mat.mNumProperties = @intCast(self.count);
        self.mat.mNumAllocated = @intCast(self.count);
    }
};

test "directoryOf keeps the trailing separator" {
    try testing.expectEqualStrings("assets/models/", converter.directoryOf("assets/models/box.gltf"));
    try testing.expectEqualStrings("C:\\models\\", converter.directoryOf("C:\\models\\box.gltf"));
}

test "directoryOf yields nothing for a bare filename" {
    try testing.expectEqualStrings("", converter.directoryOf("box.gltf"));
}

test "base colour is read from the glTF slot" {
    var f: MaterialFixture = undefined;
    f.init();
    var color = c.aiColor4D{ .r = 1.0, .g = 0.5, .b = 0.2, .a = 1.0 };
    f.add(prop("$clr.base", c.aiPTI_Float, bytesOf(c.aiColor4D, &color)));

    var md: c.ke_material_data = undefined;
    converter.convertMaterial(&f.mat, &md);
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.base_color_r, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), md.base_color_g, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.2), md.base_color_b, 1e-6);
}

test "base colour falls back to the diffuse slot" {
    var f: MaterialFixture = undefined;
    f.init();
    var color = c.aiColor4D{ .r = 0.25, .g = 0.5, .b = 0.75, .a = 1.0 };
    f.add(prop("$clr.diffuse", c.aiPTI_Float, bytesOf(c.aiColor4D, &color)));

    var md: c.ke_material_data = undefined;
    converter.convertMaterial(&f.mat, &md);
    try testing.expectApproxEqAbs(@as(f32, 0.25), md.base_color_r, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.75), md.base_color_b, 1e-6);
}

test "alpha survives the conversion" {
    var f: MaterialFixture = undefined;
    f.init();
    var color = c.aiColor4D{ .r = 1, .g = 1, .b = 1, .a = 0.35 };
    f.add(prop("$clr.base", c.aiPTI_Float, bytesOf(c.aiColor4D, &color)));

    var md: c.ke_material_data = undefined;
    converter.convertMaterial(&f.mat, &md);
    try testing.expectApproxEqAbs(@as(f32, 0.35), md.base_color_a, 1e-6);
}

test "metallic and roughness factors are read" {
    var f: MaterialFixture = undefined;
    f.init();
    var metallic: f32 = 0.8;
    var roughness: f32 = 0.2;
    f.add(prop("$mat.metallicFactor", c.aiPTI_Float, bytesOf(f32, &metallic)));
    f.add(prop("$mat.roughnessFactor", c.aiPTI_Float, bytesOf(f32, &roughness)));

    var md: c.ke_material_data = undefined;
    converter.convertMaterial(&f.mat, &md);
    try testing.expectApproxEqAbs(@as(f32, 0.8), md.metallic, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.2), md.roughness, 1e-6);
}

test "a material without PBR factors keeps the engine defaults" {
    var f: MaterialFixture = undefined;
    f.init();
    f.mat = std.mem.zeroes(c.aiMaterial);

    var md: c.ke_material_data = undefined;
    converter.convertMaterial(&f.mat, &md);
    try testing.expectApproxEqAbs(@as(f32, 0.0), md.metallic, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.5), md.roughness, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.base_color_r, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.base_color_a, 1e-6);
}

test "a triangle converts with its vertices and indices" {
    var verts = [_]c.aiVector3D{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
    };
    var idx = [_]c_uint{ 0, 1, 2 };
    var face = c.aiFace{ .mNumIndices = 3, .mIndices = &idx };

    var am: c.aiMesh = std.mem.zeroes(c.aiMesh);
    am.mNumVertices = 3;
    am.mVertices = &verts;
    am.mNumFaces = 1;
    am.mFaces = &face;

    var md: c.ke_mesh_data = undefined;
    try testing.expect(converter.convertMesh(testing.allocator, &am, &md));
    defer converter.freeMesh(testing.allocator, &md);

    try testing.expectEqual(@as(u32, 3), md.vertex_count);
    try testing.expectEqual(@as(u32, 3), md.index_count);
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.vertices[1].x, 1e-6);
    try testing.expectEqual(@as(u16, 2), md.indices[2]);
}

test "a mesh without normals gets a unit normal and a perpendicular tangent" {
    var verts = [_]c.aiVector3D{
        .{ .x = 0, .y = 0, .z = 0 },
        .{ .x = 1, .y = 0, .z = 0 },
        .{ .x = 0, .y = 1, .z = 0 },
    };
    var idx = [_]c_uint{ 0, 1, 2 };
    var face = c.aiFace{ .mNumIndices = 3, .mIndices = &idx };
    var am: c.aiMesh = std.mem.zeroes(c.aiMesh);
    am.mNumVertices = 3;
    am.mVertices = &verts;
    am.mNumFaces = 1;
    am.mFaces = &face;

    var md: c.ke_mesh_data = undefined;
    try testing.expect(converter.convertMesh(testing.allocator, &am, &md));
    defer converter.freeMesh(testing.allocator, &md);

    const v = md.vertices[0];
    try testing.expectApproxEqAbs(@as(f32, 1.0), v.nz, 1e-6);
    const tlen = @sqrt(v.tx * v.tx + v.ty * v.ty + v.tz * v.tz);
    try testing.expectApproxEqAbs(@as(f32, 1.0), tlen, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.0), v.tx * v.nx + v.ty * v.ny + v.tz * v.nz, 1e-5);
}
