//! The frame of the render service: the tag "render.frame" and the two render-phase systems that
//! begin the frame, publishing what every pass reads, and end it. It also owns their creation and
//! teardown, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_frame").logFn };

const c = @import("c");
const R = @import("result").Result(c, .{});
const log = std.log.scoped(.render_frame);
const frame_producer = @import("frame_producer.zig");

const heap = @import("heap");
const gpa = heap.gpa;

/// The state of one frame. The factory allocates it and `destroyHandle` frees it. The runtime
/// receives `producer` as the context of the begin system and the frame itself as the context of
/// the end system, and the systems' queries and access lists point into it, so it is not moved
/// after creation.
const FrameModule = struct {
    api: c.ke_render_frame,
    frame_cid: c.ke_component_id,
    producer: frame_producer.State,
    begin_access: [1]c.ke_component_access,
    end_access: [2]c.ke_component_access,
    query_terms: [4]c.ke_component_access,
    queries: [3]c.ke_query_decl,
};

fn stateOf(self: ?*c.ke_render_frame) ?*FrameModule {
    const f = self orelse return null;
    return @ptrCast(@alignCast(f.handle));
}

/// The `frame_cid` slot.
fn frameCid(self: [*c]c.ke_render_frame) callconv(.c) c.ke_component_id {
    const st = stateOf(self) orelse return c.KE_COMPONENT_INVALID;
    return st.frame_cid;
}

/// The end system: ends the frame on the service, and fails, logging the service's own error, when
/// it cannot.
fn endSystem(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) c.ke_result {
    var err_record: [*c]c.ke_error = null;
    const st: *FrameModule = @ptrCast(@alignCast(user.?));
    const core = st.producer.core;
    if (core.*.end_frame.?(core, &err_record)) return R.ok;
    return bodyFailed(err_record);
}

/// The `destroy` slot of the handle `ke_render_frame_create` returns; a null argument is ignored.
fn destroyHandle(self: ?*c.ke_render_frame) callconv(.c) void {
    const st = stateOf(self) orelse return;
    gpa.destroy(st);
}

fn refused(out_error: [*c][*c]c.ke_error) c.ke_render_frame_handle {
    c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "render frame: runtime, ecs, service and camera are required", @src().file, @intCast(@src().line), null);
    return .{ .ref = null, .destroy = null };
}

/// The factory declared in frame_create.h. A failed allocation fails as out of memory. The runtime
/// refusing either system sets the error output, removes the begin system when it was the end
/// system that was refused, and returns the null handle.
export fn ke_render_frame_create(params_in: ?*const c.ke_render_frame_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_frame_handle {
    const empty = c.ke_render_frame_handle{ .ref = null, .destroy = null };
    const p = params_in orelse return refused(out_error);
    const rt: *c.ke_runtime = p.runtime orelse return refused(out_error);
    const e: *c.ke_ecs = p.ecs orelse return refused(out_error);
    const core = p.service orelse return refused(out_error);
    const camera = p.camera orelse return refused(out_error);

    const st = gpa.create(FrameModule) catch {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "render frame: allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    st.api = .{ .handle = st, .frame_cid = frameCid };
    st.frame_cid = c.KE_COMPONENT_INVALID;
    if (e.component_register.?(e, &c.ke_component_params{ .name = "render.frame", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &st.frame_cid) != c.KE_OK)
        c.ke_error_set(out_error, &c.KE_ERROR_GENERAL, "the ECS refused a component, whose reason it logged", @src().file, @intCast(@src().line), null);
    if (st.frame_cid == c.KE_COMPONENT_INVALID) {
        gpa.destroy(st);
        return empty;
    }
    st.producer = .{ .core = core, .camera = camera };

    const rd = c.KE_ACCESS_READ;
    st.begin_access = .{.{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE }};
    st.end_access = .{
        .{ .cid = core.*.cid.?(core, c.KE_RENDER_FRAME_COLOR), .access = rd },
        .{ .cid = st.frame_cid, .access = rd },
    };
    st.query_terms = .{
        .{ .cid = p.camera_cid, .access = rd },
        .{ .cid = p.world_transform_cid, .access = rd },
        .{ .cid = p.directional_light_cid, .access = rd },
        .{ .cid = p.ambient_light_cid, .access = rd },
    };
    st.queries = .{
        .{ .terms = &st.query_terms[0], .term_count = 2 },
        .{ .terms = &st.query_terms[2], .term_count = 1 },
        .{ .terms = &st.query_terms[3], .term_count = 1 },
    };

    var begin = std.mem.zeroes(c.ke_runtime_system_params);
    begin.name = "render.begin_frame";
    begin.phase = c.KE_PHASE_RENDER;
    begin.access_list = &st.begin_access;
    begin.access_count = st.begin_access.len;
    begin.queries = &st.queries;
    begin.query_count = st.queries.len;
    begin.pinned_thread = 0;
    begin.user_data = &st.producer;
    begin.execute = frame_producer.system;
    var begin_id: c.ke_system_id = 0;
    if (rt.register_system.?(rt, &begin, &begin_id) != c.KE_OK)
        c.ke_error_set(out_error, &c.KE_ERROR_GENERAL, "the runtime refused a system, whose reason it logged", @src().file, @intCast(@src().line), null);
    if (begin_id == 0) {
        gpa.destroy(st);
        return empty;
    }

    var end = std.mem.zeroes(c.ke_runtime_system_params);
    end.name = "render.end_frame";
    end.phase = c.KE_PHASE_RENDER;
    end.access_list = &st.end_access;
    end.access_count = st.end_access.len;
    end.pinned_thread = 0;
    end.user_data = st;
    end.execute = endSystem;
    var system_id: c.ke_system_id = 0;
    if (rt.register_system.?(rt, &end, &system_id) != c.KE_OK) {
        c.ke_error_set(out_error, &c.KE_ERROR_GENERAL, "the runtime refused a system, whose reason it logged", @src().file, @intCast(@src().line), null);
        _ = rt.unregister_system.?(rt, begin_id);
        gpa.destroy(st);
        return empty;
    }

    return .{ .ref = &st.api, .destroy = destroyHandle };
}


/// The code a system body returns when a call it made failed and filled `record`, whose message is
/// logged. A bridge while the calls a body makes still report through `ke_error`.
fn bodyFailed(record: [*c]const c.ke_error) c.ke_result {
    if (record != null and record.*.message != null) log.warn("{s}", .{record.*.message});
    return R.code(error.General);
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

fn testParams(rt: *Stubs.Runtime, ecs: *Stubs.Ecs, core: *Stubs.Core, camera: *c.ke_render_camera) c.ke_render_frame_params {
    return .{ .runtime = rt.api(), .ecs = ecs.api(), .service = core.api(), .camera = camera, .camera_cid = 1, .world_transform_cid = 2, .directional_light_cid = 3, .ambient_light_cid = 4 };
}

const Rig = struct {
    dev: Stubs.Device,
    core: Stubs.Core,
    rt: Stubs.Runtime,
    ecs: Stubs.Ecs,
    camera: c.ke_render_camera,

    fn init(self: *Rig) void {
        self.dev.init();
        self.core.init(self.dev.api());
        self.rt.init();
        self.ecs.init();
        self.camera = std.mem.zeroes(c.ke_render_camera);
    }

    fn params(self: *Rig) c.ke_render_frame_params {
        return testParams(&self.rt, &self.ecs, &self.core, &self.camera);
    }
};

test "the frame registers its begin and end systems and hands out the tag they share" {
    var rig: Rig = undefined;
    rig.init();
    const h = ke_render_frame_create(&rig.params(), null);
    try testing.expect(h.ref != null);
    try testing.expectEqual(@as(u32, 2), rig.rt.live_count);
    try testing.expect(h.ref.*.frame_cid.?(h.ref) != c.KE_COMPONENT_INVALID);
    h.destroy.?(h.ref);
}

test "a frame whose end system the runtime refuses removes its begin system and fails" {
    var rig: Rig = undefined;
    rig.init();
    rig.rt.limit = 1;
    const h = ke_render_frame_create(&rig.params(), null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(u32, 0), rig.rt.live_count);
}

test "a frame the runtime refuses at once fails without registering anything" {
    var rig: Rig = undefined;
    rig.init();
    rig.rt.limit = 0;
    const h = ke_render_frame_create(&rig.params(), null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(u32, 0), rig.rt.live_count);
}

test "a frame missing its camera is refused as an invalid argument" {
    var rig: Rig = undefined;
    rig.init();
    var p = rig.params();
    p.camera = null;
    var err: [*c]c.ke_error = null;
    try testing.expect(ke_render_frame_create(&p, &err).ref == null);
    try testing.expect(err != null);
    try testing.expectEqual(&c.KE_ERROR_INVALID_ARGUMENT, err.*.type);
}

fn failingFrame(_: [*c]c.ke_render_service, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "no backbuffer", @src().file, @intCast(@src().line), null);
    return false;
}

test "a frame the service cannot begin or end fails the render phase with the service's own error" {
    var svc = std.mem.zeroes(c.ke_render_service);
    svc.begin_frame = failingFrame;
    svc.end_frame = failingFrame;
    var camera = std.mem.zeroes(c.ke_render_camera);
    var st: FrameModule = undefined;
    st.producer = .{ .core = &svc, .camera = &camera };

    try testing.expect(frame_producer.system(null, &st.producer, 0.0) != R.ok);

    try testing.expect(endSystem(null, &st, 0.0) != R.ok);
}

test "creating and destroying the frame leaves no block allocated" {
    try heap.expectNoLeaks();
}
