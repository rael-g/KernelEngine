const std = @import("std");

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed.
pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/render_core_create.h");
    @cInclude("kernel_engine/render/core/render_module_create.h");
});

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

// The device is borrowed (caller-owned); only the render core is owned here.
const ModuleState = struct {
    core: c.ke_render_core_handle,
    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    bb_write_access: [1]c.ke_component_access,
    bb_read_access: [1]c.ke_component_access,
};

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

// ── Render-phase systems (ordered by the backbuffer tag-cid: begin → clear → end) ─

fn beginFrameSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    _ = ctx;
    _ = dt;
    const st = stateOf(user);
    _ = st.core.ref.*.begin_frame.?(st.core.ref, null);
}

fn clearSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    _ = dt;
    const st = stateOf(user);
    const pc = st.core.ref.*.begin_pass.?(st.core.ref, ctx, &st.io);
    if (pc == null) return;
    // begin_render binds the backbuffer with load_op CLEAR; no draws → clear only.
    const rp = pc.*.begin_render.?(pc);
    rp.*.end.?(rp);
    st.core.ref.*.end_pass.?(st.core.ref, pc);
}

fn endFrameSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    _ = ctx;
    _ = dt;
    const st = stateOf(user);
    _ = st.core.ref.*.end_frame.?(st.core.ref, null);
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8, access: [*c]c.ke_component_access,
               user: *ModuleState, exec: ExecFn) void {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name          = name;
    params.phase         = c.KE_PHASE_RENDER;
    params.access_list   = access;
    params.access_count  = 1;
    params.pinned_thread = 0;
    params.user_data     = user;
    params.execute       = exec;
    _ = rt.register_system.?(rt, &params, null);
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    if (st.core.destroy) |d| d(st.core.ref);
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs,
                                  device: ?*c.ke_gpu_device, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const dev = device orelse return empty;

    const core_h = c.ke_render_core_create(dev, e, out_error);
    if (core_h.ref == null) return empty;

    const st = gpa.create(ModuleState) catch {
        if (core_h.destroy) |d| d(core_h.ref);
        return empty;
    };
    st.core = core_h;
    st.bb_writes = .{"backbuffer"};
    st.io = std.mem.zeroes(c.ke_render_pass_io);
    st.io.writes = @ptrCast(&st.bb_writes);
    st.io.writes_count = 1;

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    st.bb_write_access = .{.{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE }};
    st.bb_read_access = .{.{ .cid = bb_cid, .access = c.KE_ACCESS_READ }};

    registerSys(rt, "render.begin_frame", &st.bb_write_access, st, beginFrameSys);
    registerSys(rt, "render.clear",       &st.bb_write_access, st, clearSys);
    registerSys(rt, "render.end_frame",   &st.bb_read_access,  st, endFrameSys);

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
