// aiMesh / aiMaterial -> the engine's ke_mesh_data / ke_material_data.
//
// Assimp's C++ accessors (HasNormals(), Get(AI_MATKEY_...)) have no counterpart
// in the C API, so presence is tested by null-checking the arrays directly and
// material values are read through the aiGetMaterial* family.

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

pub fn convertMesh(am: *const c.aiMesh, md: *c.ke_mesh_data) bool {
    md.* = std.mem.zeroes(c.ke_mesh_data);
    log.copyString(&md.name, &am.mName.data);
    md.vertex_count = am.mNumVertices;

    const index_capacity = am.mNumFaces * 3;
    const vertices: [*]c.ke_vertex = @ptrCast(@alignCast(
        c.ke_alloc(@sizeOf(c.ke_vertex) * am.mNumVertices, @alignOf(c.ke_vertex)) orelse return false,
    ));
    const indices: [*]u16 = @ptrCast(@alignCast(
        c.ke_alloc(@sizeOf(u16) * index_capacity, @alignOf(u16)) orelse {
            c.ke_free(vertices);
            return false;
        },
    ));
    md.vertices = vertices;
    md.indices = indices;

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
            // Handedness: sign of dot(cross(n, t), bitangent).
            const cx = n.y * t.z - n.z * t.y;
            const cy = n.z * t.x - n.x * t.z;
            const cz = n.x * t.y - n.y * t.x;
            v.tw = if (cx * bt.x + cy * bt.y + cz * bt.z >= 0) 1 else -1;
        } else {
            // Uses the normal resolved above, which defaults to (0,0,1) for a
            // mesh without normals — reading am.mNormals here would dereference
            // null in exactly that case.
            const t = fallbackTangent(v.nx, v.ny, v.nz);
            v.tx = t[0];
            v.ty = t[1];
            v.tz = t[2];
            v.tw = 1;
        }
    }

    // Triangulation is requested at import, but a degenerate face can still
    // carry fewer than three indices; the cursor records what was really
    // written rather than assuming three per face.
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

    // glTF-style base colour first, falling back to the classic diffuse slot.
    var color = c.aiColor4D{ .r = 1, .g = 1, .b = 1, .a = 1 };
    if (!getColor(am, MatKey.base_color, &color)) {
        _ = getColor(am, MatKey.color_diffuse, &color);
    }
    md.base_color_r = color.r;
    md.base_color_g = color.g;
    md.base_color_b = color.b;
    md.base_color_a = color.a;

    // Defaults stand when the material declares no PBR factors.
    var metallic: f32 = 0.0;
    var roughness: f32 = 0.5;
    _ = getFloat(am, MatKey.metallic_factor, &metallic);
    _ = getFloat(am, MatKey.roughness_factor, &roughness);
    md.metallic = metallic;
    md.roughness = roughness;
}
