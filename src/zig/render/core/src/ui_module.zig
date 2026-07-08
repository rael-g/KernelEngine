const std = @import("std");
const cimport = @import("cimport.zig");
const c = cimport.c;

// UI overlay pass — draws whatever ui_quad calls (Font/Label systems, game HUD
// code) queued this frame. The core owns the pipeline and quad list entirely;
// this module just declares the pass I/O (loads, doesn't clear, the backbuffer
// tonemap wrote) and forwards ctx/io so ui_draw can begin/end its own pass.

pub const UiModule = struct {
    core: c.ke_render_core_handle = undefined,

    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [1]c.ke_component_access = undefined,
};

inline fn moduleOf(user: ?*anyopaque) *UiModule {
    return @alignCast(@ptrCast(user.?));
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const ui = moduleOf(user);
    ui.core.ref.*.ui_draw.?(ui.core.ref, ctx, &ui.io);
}

// cmd_slot is the caller's frame-command-slot ordering (after tonemap); bb_cid
// is the backbuffer tag-cid the caller already resolved for the frame barrier.
pub fn setup(ui: *UiModule, core: c.ke_render_core_handle, bb_cid: c.ke_component_id, cmd_slot: u32) void {
    ui.core = core;
    ui.writes = .{"backbuffer"};
    ui.io = std.mem.zeroes(c.ke_render_pass_io);
    ui.io.writes = @ptrCast(&ui.writes);
    ui.io.writes_count = 1;
    ui.io.cmd_slot = cmd_slot;
    ui.io.load = 1; // loads (doesn't clear) — composites over the tonemapped scene
    ui.access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
    };
}
