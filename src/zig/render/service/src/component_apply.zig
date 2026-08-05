// Per-component apply callbacks for render's own scene-file component
// vocabulary (camera/mesh/directional_light/point_light/spot_light). Each one
// translates a variant-table entry list into the matching component's raw
// memory. Registered against the caller-supplied ke_world by render_module.zig
// itself — the framework plugin owns none of this, it only owns "transform"
// (see src/zig/framework/src/components_apply.zig).
//
// Conventions:
//   - Field name matching is case-sensitive and exact ("color" != "Color").
//   - Type mismatches are silently skipped (loader semantics: unknown <-> ignore).
//   - Vec arrays from TOML come pre-converted to KE_VARIANT_VEC2/VEC3/VEC4 by
//     the scene_loader's toml->variant pass. A 3-element array becomes VEC3;
//     applies decide whether they want VEC3 or VEC4.

const std = @import("std");

const c = @import("cimport.zig").c;

const pi: f32 = 3.14159265358979323846;

/// Entries arrive as a C pointer + count; the callbacks only ever read them.
fn entries(e: [*c]const c.ke_variant_table_entry, n: u32) []const c.ke_variant_table_entry {
    if (n == 0) return &.{};
    return e[0..n];
}

fn keyIs(entry: *const c.ke_variant_table_entry, name: []const u8) bool {
    if (entry.key == null) return false;
    return std.mem.eql(u8, std.mem.span(entry.key), name);
}

fn asFloat(v: *const c.ke_variant) ?f32 {
    return switch (v.type) {
        c.KE_VARIANT_FLOAT => @floatCast(v.unnamed_0.f),
        c.KE_VARIANT_INT => @floatFromInt(v.unnamed_0.i),
        else => null,
    };
}

// -- camera ------------------------------------------------------------------

pub export fn ke_render_apply_camera(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const cam: *c.ke_camera_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "fov")) {
            if (asFloat(v)) |f| cam.fov = f;
        } else if (keyIs(entry, "fov_degrees")) {
            // Convenient alias: scene file says degrees, component stores radians.
            if (asFloat(v)) |f| cam.fov = f * (pi / 180.0);
        } else if (keyIs(entry, "near_plane")) {
            if (asFloat(v)) |f| cam.near_plane = f;
        } else if (keyIs(entry, "far_plane")) {
            if (asFloat(v)) |f| cam.far_plane = f;
        } else if (keyIs(entry, "orthographic_size")) {
            if (asFloat(v)) |f| cam.orthographic_size = f;
        } else if (keyIs(entry, "orthographic")) {
            if (v.type == c.KE_VARIANT_BOOL) {
                cam.orthographic = if (v.unnamed_0.b) 1 else 0;
            } else if (v.type == c.KE_VARIANT_INT) {
                cam.orthographic = if (v.unnamed_0.i != 0) 1 else 0;
            }
        }
    }
}

// -- mesh --------------------------------------------------------------------

pub export fn ke_render_apply_mesh(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const m: *c.ke_mesh_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "primitive") and v.type == c.KE_VARIANT_STRING and v.unnamed_0.s != null) {
            const src = std.mem.span(v.unnamed_0.s);
            const len = @min(src.len, m.primitive.len - 1);
            @memcpy(m.primitive[0..len], src[0..len]);
            m.primitive[len] = 0;
        }
        // Color is a material property (base-color factor), not a mesh-component
        // field — scene-file material specification is a future loader feature.
    }
}

// -- directional light -------------------------------------------------------

pub export fn ke_render_apply_directional_light(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const l: *c.ke_directional_light_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "direction")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.direction[0] = v.unnamed_0.v3.x;
                l.direction[1] = v.unnamed_0.v3.y;
                l.direction[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "color")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.color[0] = v.unnamed_0.v3.x;
                l.color[1] = v.unnamed_0.v3.y;
                l.color[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "ambient")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.ambient[0] = v.unnamed_0.v3.x;
                l.ambient[1] = v.unnamed_0.v3.y;
                l.ambient[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "intensity")) {
            if (asFloat(v)) |f| l.intensity = f;
        } else if (keyIs(entry, "dir_x")) {
            if (asFloat(v)) |f| l.direction[0] = f;
        } else if (keyIs(entry, "dir_y")) {
            if (asFloat(v)) |f| l.direction[1] = f;
        } else if (keyIs(entry, "dir_z")) {
            if (asFloat(v)) |f| l.direction[2] = f;
        } else if (keyIs(entry, "r")) {
            if (asFloat(v)) |f| l.color[0] = f;
        } else if (keyIs(entry, "g")) {
            if (asFloat(v)) |f| l.color[1] = f;
        } else if (keyIs(entry, "b")) {
            if (asFloat(v)) |f| l.color[2] = f;
        }
    }
}

// -- point light -------------------------------------------------------------

pub export fn ke_render_apply_point_light(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const l: *c.ke_point_light_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "color")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.color[0] = v.unnamed_0.v3.x;
                l.color[1] = v.unnamed_0.v3.y;
                l.color[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "radius")) {
            if (asFloat(v)) |f| l.radius = f;
        } else if (keyIs(entry, "intensity")) {
            if (asFloat(v)) |f| l.intensity = f;
        } else if (keyIs(entry, "r")) {
            if (asFloat(v)) |f| l.color[0] = f;
        } else if (keyIs(entry, "g")) {
            if (asFloat(v)) |f| l.color[1] = f;
        } else if (keyIs(entry, "b")) {
            if (asFloat(v)) |f| l.color[2] = f;
        }
    }
}

// -- spot light --------------------------------------------------------------

pub export fn ke_render_apply_spot_light(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const l: *c.ke_spot_light_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        const v = &entry.value;
        if (keyIs(entry, "direction")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.direction[0] = v.unnamed_0.v3.x;
                l.direction[1] = v.unnamed_0.v3.y;
                l.direction[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "color")) {
            if (v.type == c.KE_VARIANT_VEC3) {
                l.color[0] = v.unnamed_0.v3.x;
                l.color[1] = v.unnamed_0.v3.y;
                l.color[2] = v.unnamed_0.v3.z;
            }
        } else if (keyIs(entry, "inner_angle")) {
            if (asFloat(v)) |f| l.inner_angle = f;
        } else if (keyIs(entry, "outer_angle")) {
            if (asFloat(v)) |f| l.outer_angle = f;
        } else if (keyIs(entry, "range")) {
            if (asFloat(v)) |f| l.range = f;
        } else if (keyIs(entry, "intensity")) {
            if (asFloat(v)) |f| l.intensity = f;
        } else if (keyIs(entry, "dir_x")) {
            if (asFloat(v)) |f| l.direction[0] = f;
        } else if (keyIs(entry, "dir_y")) {
            if (asFloat(v)) |f| l.direction[1] = f;
        } else if (keyIs(entry, "dir_z")) {
            if (asFloat(v)) |f| l.direction[2] = f;
        } else if (keyIs(entry, "r")) {
            if (asFloat(v)) |f| l.color[0] = f;
        } else if (keyIs(entry, "g")) {
            if (asFloat(v)) |f| l.color[1] = f;
        } else if (keyIs(entry, "b")) {
            if (asFloat(v)) |f| l.color[2] = f;
        }
    }
}
