// What the generated ke_component_field tables in
// kernel_engine/render/component_fields.h cannot express for render's scene-file
// component vocabulary. Every plain field — name, offset, type, coercion — is
// described by the table and applied by the framework before these run; what is
// left here is the handful of keys whose meaning is not "write this value at
// this offset".
//
// A callback registered for a component runs after that component's table, so
// these only ever correct or add.

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

/// `fov_degrees` is the same field as `fov` in a different unit. A table maps a
/// key to storage; it has no way to say "and multiply by pi/180".
pub export fn ke_render_apply_camera(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const cam: *c.ke_camera_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "fov_degrees")) continue;
        if (asFloat(&entry.value)) |f| cam.fov = f * (pi / 180.0);
    }
}

fn alphaModeOf(v: *const c.ke_variant) ?u32 {
    if (v.type != c.KE_VARIANT_STRING or v.unnamed_0.s == null) return null;
    const mode = std.mem.span(v.unnamed_0.s);
    if (std.mem.eql(u8, mode, "mask")) return c.KE_ALPHA_MODE_MASK;
    if (std.mem.eql(u8, mode, "blend")) return c.KE_ALPHA_MODE_BLEND;
    return c.KE_ALPHA_MODE_OPAQUE;
}

/// `alpha_mode` is authored as the enumerator's name rather than its number.
/// The table would write the string's bytes over a uint32_t; naming an
/// enumerator is a mapping only the domain that declares the enum holds.
pub export fn ke_render_apply_mesh(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const m: *c.ke_mesh_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        if (alphaModeOf(&entry.value)) |mode| m.alpha_mode = mode;
    }
}

/// Same enumerator-by-name mapping as a mesh's, for the same reason.
pub export fn ke_render_apply_sprite2d(ptr: ?*anyopaque, e: [*c]const c.ke_variant_table_entry, n: u32) callconv(.c) void {
    const sp: *c.ke_sprite2d_component = @ptrCast(@alignCast(ptr));
    for (entries(e, n)) |*entry| {
        if (!keyIs(entry, "alpha_mode")) continue;
        if (alphaModeOf(&entry.value)) |mode| sp.alpha_mode = mode;
    }
}
