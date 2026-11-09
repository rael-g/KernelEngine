//! The frame of the render service: the tag "render.frame" and the two render-phase systems that
//! begin the frame, publishing what every pass reads, and end it. It also owns their creation and
//! teardown, behind the one factory it exports.

const abi_framework = @import("abi_framework");
const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_frame").logFn };

const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_frame_factory = @import("abi_render_frame_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_frame);
const frame_producer = @import("frame_producer.zig");

const heap = @import("heap");
const gpa = heap.gpa;

/// The state of one frame. The factory allocates it and `destroyHandle` frees it. The runtime
/// receives `producer` as the context of the begin system and the frame itself as the context of
/// the end system, and the systems' queries and access lists point into it, so it is not moved
/// after creation. `destroyHandle` unregisters both systems before it frees the frame.
const FrameModule = struct {
    api: abi_render.c.ke_render_frame,
    runtime: *abi_runtime.c.ke_runtime,
    systems: [2]abi_runtime.c.ke_system_id,
    frame_cid: abi_asset_resolver.c.ke_component_id,
    producer: frame_producer.State,
    begin_access: [1]abi_runtime.c.ke_component_access,
    end_access: [2]abi_runtime.c.ke_component_access,
    query_terms: [4]abi_runtime.c.ke_component_access,
    queries: [3]abi_runtime.c.ke_query_decl,
};

fn stateOf(self: ?*abi_render.c.ke_render_frame) ?*FrameModule {
    const f = self orelse return null;
    return @ptrCast(@alignCast(f.handle));
}

/// The `frame_cid` slot.
fn frameCid(self: [*c]abi_render.c.ke_render_frame) callconv(.c) abi_asset_resolver.c.ke_component_id {
    const st = stateOf(self) orelse return abi_ecs.c.KE_COMPONENT_INVALID;
    return st.frame_cid;
}

/// The end system: ends the frame on the service, failing with the service's code when it cannot.
fn endSystem(_: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const st: *FrameModule = @ptrCast(@alignCast(user.?));
    const core = st.producer.core;
    return core.*.end_frame.?(core);
}

/// The `destroy` slot of the handle `ke_render_frame_create` returns; a null argument is ignored.
fn destroyHandle(self: ?*abi_render.c.ke_render_frame) callconv(.c) void {
    const st = stateOf(self) orelse return;
    for (st.systems) |id| _ = st.runtime.unregister_system.?(st.runtime, id);
    gpa.destroy(st);
}

/// The factory declared in frame_create.h. A missing runtime, ecs, service or camera fails as an
/// invalid argument and a failed allocation as out of memory. The runtime refusing either system
/// fails with the runtime's code, after removing the begin system when it was the end system that
/// was refused. Each failure leaves the handle zeroed.
export fn ke_render_frame_create(params_in: ?*const abi_render_frame_factory.c.ke_render_frame_params, out_frame: ?*abi_render.c.ke_render_frame_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_frame orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return refused();
    out.* = create(p.runtime orelse return refused(), p.ecs orelse return refused(), p.service orelse return refused(), p.camera orelse return refused(), blk: { if (p.scene == null) return refused(); break :blk p; }) catch |err| return R.code(err);
    return R.ok;
}

fn refused() abi_result.c.ke_result {
    log.warn("render frame: runtime, ecs, service, camera and scene are required", .{});
    return R.code(error.InvalidArgument);
}

fn create(rt: *abi_runtime.c.ke_runtime, e: *abi_ecs.c.ke_ecs, core: *abi_render.c.ke_render_service, camera: *abi_render.c.ke_render_camera, p: *const abi_render_frame_factory.c.ke_render_frame_params) R.Error!abi_render.c.ke_render_frame_handle {
    const st = try gpa.create(FrameModule);
    errdefer gpa.destroy(st);
    st.api = .{ .handle = st, .frame_cid = frameCid };
    st.frame_cid = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_params{ .name = "render.frame", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &st.frame_cid));
    st.producer = .{ .core = core, .camera = camera };

    const ids = p.scene.?.component_ids.?(p.scene);
    const rd = abi_runtime.c.KE_ACCESS_READ;
    st.begin_access = .{.{ .cid = st.frame_cid, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    st.end_access = .{
        .{ .cid = core.*.frame_color.?(core), .access = rd },
        .{ .cid = st.frame_cid, .access = rd },
    };
    st.query_terms = .{
        .{ .cid = ids.?.camera, .access = rd },
        .{ .cid = ids.?.world_transform, .access = rd },
        .{ .cid = ids.?.directional_light, .access = rd },
        .{ .cid = ids.?.ambient_light, .access = rd },
    };
    st.queries = .{
        .{ .terms = st.query_terms[0..].ptr, .term_count = 2 },
        .{ .terms = st.query_terms[2..].ptr, .term_count = 1 },
        .{ .terms = st.query_terms[3..].ptr, .term_count = 1 },
    };

    var begin = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    begin.name = "render.begin_frame";
    begin.phase = abi_runtime.c.KE_PHASE_RENDER;
    begin.access_list = &st.begin_access;
    begin.access_count = st.begin_access.len;
    begin.queries = &st.queries;
    begin.query_count = st.queries.len;
    begin.user_data = &st.producer;
    begin.execute = frame_producer.system;
    var begin_id: abi_runtime.c.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &begin, &begin_id));
    errdefer _ = rt.unregister_system.?(rt, begin_id);

    var end = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    end.name = "render.end_frame";
    end.phase = abi_runtime.c.KE_PHASE_RENDER;
    end.access_list = &st.end_access;
    end.access_count = st.end_access.len;
    end.user_data = st;
    end.execute = endSystem;
    var system_id: abi_runtime.c.ke_system_id = 0;
    try R.check(rt.register_system.?(rt, &end, &system_id));
    st.runtime = rt;
    st.systems = .{ begin_id, system_id };

    return .{ .ref = &st.api, .destroy = destroyHandle };
}

const testing = std.testing;

const zsub = @import("zsub");

fn testFrame(params: *const abi_render_frame_factory.c.ke_render_frame_params) abi_render.c.ke_render_frame_handle {
    var h: abi_render.c.ke_render_frame_handle = .{ .ref = null, .destroy = null };
    _ = ke_render_frame_create(params, &h);
    return h;
}

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .camera = 1, .world_transform = 2, .directional_light = 3, .ambient_light = 4 });

fn testComponentIds(_: [*c]abi_render.c.ke_render_scene_resolve) callconv(.c) [*c]const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds };

const Rig = struct {
    core: zsub.For(abi_render.c.ke_render_service),
    rt: zsub.For(abi_runtime.c.ke_runtime),
    ecs: zsub.For(abi_ecs.c.ke_ecs),
    camera: abi_render.c.ke_render_camera,

    fn init(self: *Rig) !void {
        try self.core.init();
        _ = self.core.when(.frame_color).returnsFresh();
        _ = self.core.when(.frame_depth).returnsFresh();
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
        try self.ecs.init();
        _ = self.ecs.when(.component_register).writesFresh(2);
        self.camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    }

    fn deinit(self: *Rig) void {
        self.ecs.deinit();
        self.rt.deinit();
        self.core.deinit();
    }

    fn params(self: *Rig) abi_render_frame_factory.c.ke_render_frame_params {
        return .{ .runtime = self.rt.api(), .ecs = self.ecs.api(), .service = self.core.api(), .camera = &self.camera, .scene = &test_scene };
    }
};

test "the frame registers its begin and end systems and hands out the tag they share" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = testFrame(&rig.params());
    try testing.expect(h.ref != null);
    try rig.rt.received(.register_system).times(2);
    try rig.rt.received(.unregister_system).never();
    try testing.expect(h.ref.?.frame_cid.?(h.ref) != abi_ecs.c.KE_COMPONENT_INVALID);
    h.destroy.?(h.ref);
}

test "destroying the frame unregisters both its systems" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = testFrame(&rig.params());
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a frame whose end system the runtime refuses removes its begin system and fails" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returnsSeq(&.{ abi_result.c.KE_OK, abi_result.c.KE_RESULT_OUT_OF_MEMORY });
    const h = testFrame(&rig.params());
    try testing.expect(h.ref == null);
    try rig.rt.received(.unregister_system).times(1);
}

test "a frame the runtime refuses at once fails without registering anything" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    const h = testFrame(&rig.params());
    try testing.expect(h.ref == null);
    try rig.rt.received(.register_system).times(1);
    try rig.rt.received(.unregister_system).never();
}

test "a frame missing its camera is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var p = rig.params();
    p.camera = null;
    var h: abi_render.c.ke_render_frame_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_frame_create(&p, &h));
    try testing.expect(h.ref == null);
}

fn failingFrame(_: [*c]abi_render.c.ke_render_service) callconv(.c) abi_result.c.ke_result {
    return R.code(error.NotInitialized);
}

test "a frame the service cannot begin or end fails the render phase with the service's own code" {
    var svc = std.mem.zeroes(abi_render.c.ke_render_service);
    svc.begin_frame = failingFrame;
    svc.end_frame = failingFrame;
    var camera = std.mem.zeroes(abi_render.c.ke_render_camera);
    var st: FrameModule = undefined;
    st.producer = .{ .core = &svc, .camera = &camera };

    try testing.expectEqual(R.code(error.NotInitialized), frame_producer.system(null, &st.producer, 0.0));

    try testing.expectEqual(R.code(error.NotInitialized), endSystem(null, &st, 0.0));
}

test "creating and destroying the frame leaves no block allocated" {
    try heap.expectNoLeaks();
}
