// Tests for the assimp->engine conversion.
//
// These replace the C++ unit tests that compiled the converter directly. That
// suite built materials with aiMaterial::AddProperty, a C++ method the C API
// does not mirror, so the fixtures here assemble aiMaterial/aiMesh as the plain
// structs they are and let the aiGetMaterial* readers walk them.

const std = @import("std");
const testing = std.testing;

const c = @import("c.zig").c;
const converter = @import("converter.zig");

// -- fixtures ----------------------------------------------------------------

fn aiStr(text: []const u8) c.aiString {
    var s: c.aiString = std.mem.zeroes(c.aiString);
    s.length = @intCast(text.len);
    @memcpy(s.data[0..text.len], text);
    return s;
}

/// One material property, laid out the way assimp's readers expect: key,
/// semantic/index pair, and a raw byte payload tagged with its type.
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
        // Rebuilt every time: the pointer array must reference the stored
        // properties, which move as the fixture is filled in place.
        for (0..self.count) |i| self.ptrs[i] = &self.props[i];
        self.mat.mProperties = &self.ptrs;
        self.mat.mNumProperties = @intCast(self.count);
        self.mat.mNumAllocated = @intCast(self.count);
    }
};

// -- directory ---------------------------------------------------------------

test "directoryOf keeps the trailing separator" {
    try testing.expectEqualStrings("assets/models/", converter.directoryOf("assets/models/box.gltf"));
    try testing.expectEqualStrings("C:\\models\\", converter.directoryOf("C:\\models\\box.gltf"));
}

test "directoryOf yields nothing for a bare filename" {
    try testing.expectEqualStrings("", converter.directoryOf("box.gltf"));
}

// -- material ----------------------------------------------------------------

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
    // An absent colour reads as opaque white rather than transparent black.
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.base_color_r, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), md.base_color_a, 1e-6);
}

// -- mesh --------------------------------------------------------------------

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
    try testing.expect(converter.convertMesh(&am, &md));
    defer {
        if (md.vertices) |v| c.ke_free(v);
        if (md.indices) |i| c.ke_free(i);
    }

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
    try testing.expect(converter.convertMesh(&am, &md));
    defer {
        if (md.vertices) |v| c.ke_free(v);
        if (md.indices) |i| c.ke_free(i);
    }

    const v = md.vertices[0];
    try testing.expectApproxEqAbs(@as(f32, 1.0), v.nz, 1e-6);
    // The generated tangent must be unit length and perpendicular to the normal,
    // or normal mapping would read a skewed basis.
    const tlen = @sqrt(v.tx * v.tx + v.ty * v.ty + v.tz * v.tz);
    try testing.expectApproxEqAbs(@as(f32, 1.0), tlen, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.0), v.tx * v.nx + v.ty * v.ny + v.tz * v.nz, 1e-5);
}
