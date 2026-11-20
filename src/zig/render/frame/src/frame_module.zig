//! The frame of the render world: the tag "render.frame", the frame every pass declares into the
//! render graph, and the module whose systems begin that frame and execute and present it. It owns
//! their creation and teardown, behind the two factories it exports.

const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_render_gpu = @import("abi_render_gpu");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_frame").logFn };

const abi_completion = @import("abi_completion");
const abi_ecs = @import("abi_ecs");
const abi_part = @import("abi_part");
const part = @import("part");
const hooked_systems = @import("hooked_systems");
const abi_render = @import("abi_render");
const abi_render_frame_factory = @import("abi_render_frame_factory");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_frame);
const frame_producer = @import("frame_producer.zig");

const heap = @import("heap");
const gpa = heap.gpa;

const g = abi_render_graph.c;
const Frame = abi_render_frame.c.ke_render_frame;
/// The frame's settings, with this implementation's defaults.
const Settings = struct {
    clear_color: [4]f32 = .{ 0.0, 0.0, 0.0, 1.0 },
    color_format: ColorFormat = .rgba16_float,
    depth_format: DepthFormat = .d32_float,

    pub const ranges = .{ .clear_color = .{ 0.0, 1.0 } };
};

/// The formats a frame's colour can take, named as a person writes them.
const ColorFormat = enum {
    rgba8_unorm,
    rgba8_srgb,
    bgra8_unorm,
    rgba16_float,
    rgba32_float,

    fn gpu(f: ColorFormat) abi_render_gpu.c.ke_gpu_texture_format {
        return switch (f) {
            .rgba8_unorm => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
            .rgba8_srgb => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_SRGB,
            .bgra8_unorm => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM,
            .rgba16_float => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
            .rgba32_float => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA32_FLOAT,
        };
    }
};

/// The formats a frame's depth can take, named as a person writes them.
const DepthFormat = enum {
    d16_unorm,
    d24_unorm_s8_uint,
    d32_float,
    d32_float_s8_uint,

    fn gpu(f: DepthFormat) abi_render_gpu.c.ke_gpu_texture_format {
        return switch (f) {
            .d16_unorm => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D16_UNORM,
            .d24_unorm_s8_uint => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT,
            .d32_float => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
            .d32_float_s8_uint => abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT,
        };
    }
};

/// One resource a pass published in the frame being declared, under a name the frame owns.
const Published = struct {
    name: [:0]u8,
    resource: g.ke_render_graph_resource,
};

/// The state of one frame. The factory allocates it and `destroyFrame` frees it. The frame's
/// resources and published names are those of the frame being declared, renewed by `beginSystem`;
/// `live` is false until a frame begins with a view to draw into. Its systems and queries point into
/// it, so it is not moved after creation.
const State = struct {
    api: Frame,
    graph: *g.ke_render_graph,
    service: *abi_render.c.ke_render_service,
    producer: frame_producer.State,
    frame_cid: abi_ecs.c.ke_component_id,
    color_format: abi_render_gpu.c.ke_gpu_texture_format,
    depth_format: abi_render_gpu.c.ke_gpu_texture_format,
    clear_color: [4]f32,
    live: bool = false,
    claimed: bool = false,
    color: g.ke_render_graph_resource = g.KE_RENDER_GRAPH_RESOURCE_INVALID,
    depth: g.ke_render_graph_resource = g.KE_RENDER_GRAPH_RESOURCE_INVALID,
    output: g.ke_render_graph_resource = g.KE_RENDER_GRAPH_RESOURCE_INVALID,
    output_format: abi_render_gpu.c.ke_gpu_texture_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID,
    published: std.ArrayList(Published) = .empty,
    systems: hooked_systems.Systems(2) = .{},
    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    query_terms: [4]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [3]abi_ecs.c.ke_ecs_query_desc = undefined,
};

fn stateOf(self: ?*Frame) ?*State {
    return @ptrCast(@alignCast((self orelse return null).handle));
}

/// Slot `frame_cid`.
fn frameCid(self: ?*Frame) callconv(.c) abi_ecs.c.ke_component_id {
    return (stateOf(self) orelse return abi_ecs.c.KE_COMPONENT_INVALID).frame_cid;
}

/// Slot `graph`.
fn graphOf(self: ?*Frame) callconv(.c) ?*g.ke_render_graph {
    return (stateOf(self) orelse return null).graph;
}

/// Slot `live`.
fn liveOf(self: ?*Frame) callconv(.c) bool {
    return (stateOf(self) orelse return false).live;
}

/// Slot `color`.
fn colorOf(self: ?*Frame) callconv(.c) g.ke_render_graph_resource {
    return (stateOf(self) orelse return g.KE_RENDER_GRAPH_RESOURCE_INVALID).color;
}

/// Slot `depth`.
fn depthOf(self: ?*Frame) callconv(.c) g.ke_render_graph_resource {
    return (stateOf(self) orelse return g.KE_RENDER_GRAPH_RESOURCE_INVALID).depth;
}

/// Slot `output`.
fn outputOf(self: ?*Frame) callconv(.c) g.ke_render_graph_resource {
    return (stateOf(self) orelse return g.KE_RENDER_GRAPH_RESOURCE_INVALID).output;
}

/// Slot `claim_output`.
fn claimOutput(self: ?*Frame) callconv(.c) void {
    (stateOf(self) orelse return).claimed = true;
}

/// Slot `publish`: replaces the resource of a name already published, or copies the name.
fn publish(self: ?*Frame, name_in: ?[*:0]const u8, resource: g.ke_render_graph_resource) callconv(.c) abi_result.c.ke_result {
    const st = stateOf(self) orelse return R.code(error.InvalidArgument);
    const name = std.mem.span(name_in orelse return R.code(error.InvalidArgument));
    for (st.published.items) |*p| if (std.mem.eql(u8, p.name, name)) {
        p.resource = resource;
        return R.ok;
    };
    const owned = gpa.dupeZ(u8, name) catch return R.code(error.OutOfMemory);
    st.published.append(gpa, .{ .name = owned, .resource = resource }) catch {
        gpa.free(owned);
        return R.code(error.OutOfMemory);
    };
    return R.ok;
}

/// Slot `find`.
fn find(self: ?*Frame, name_in: ?[*:0]const u8) callconv(.c) g.ke_render_graph_resource {
    const st = stateOf(self) orelse return g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const name = std.mem.span(name_in orelse return g.KE_RENDER_GRAPH_RESOURCE_INVALID);
    for (st.published.items) |p| if (std.mem.eql(u8, p.name, name)) return p.resource;
    return g.KE_RENDER_GRAPH_RESOURCE_INVALID;
}

/// Slot `color_format`.
fn colorFormat(self: ?*Frame) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    return (stateOf(self) orelse return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID).color_format;
}

/// Slot `depth_format`.
fn depthFormat(self: ?*Frame) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    return (stateOf(self) orelse return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID).depth_format;
}

/// Slot `output_format`: the render target's format, asked of the service.
fn outputFormat(self: ?*Frame) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
    const st = stateOf(self) orelse return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID;
    return st.service.*.backbuffer_format.?(st.service);
}

fn forgetPublished(st: *State) void {
    for (st.published.items) |p| gpa.free(p.name);
    st.published.clearRetainingCapacity();
}

fn recordNothing(_: ?*anyopaque, _: ?*g.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    return R.ok;
}

fn recordBlit(user: ?*anyopaque, ctx: ?*g.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const st: *State = @ptrCast(@alignCast(user.?));
    const c = ctx.?;
    st.service.*.blit.?(st.service, @ptrCast(c.render_pass.?(c)), c.texture_view.?(c, st.color), st.output_format);
    return R.ok;
}

fn frameTexture(st: *State, name: [*:0]const u8, format: abi_render_gpu.c.ke_gpu_texture_format) R.Error!g.ke_render_graph_resource {
    var desc = std.mem.zeroes(g.ke_render_graph_texture_desc);
    desc.name = name;
    desc.format = format;
    desc.size_class = g.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    desc.mip_levels = 1;
    desc.array_layers = 1;
    desc.samples = 1;
    var id: g.ke_render_graph_resource = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    try R.check(st.graph.create_texture.?(st.graph, &desc, &id));
    return id;
}

fn use(resource: g.ke_render_graph_resource, usage: g.ke_render_graph_usage, load: g.ke_render_graph_load) g.ke_render_graph_use {
    var u = std.mem.zeroes(g.ke_render_graph_use);
    u.resource = resource;
    u.usage = usage;
    u.load = load;
    return u;
}

/// Begins the graph's frame over the acquired view: imports it as the output, makes the colour and
/// the depth the size of the output, and declares the pass that clears them.
fn declareFrame(st: *State, view: abi_render_gpu.c.ke_gpu_texture_view) R.Error!void {
    var w: u32 = 0;
    var h: u32 = 0;
    st.service.*.backbuffer_size.?(st.service, &w, &h);
    try R.check(st.graph.begin_frame.?(st.graph, w, h));
    st.output_format = st.service.*.backbuffer_format.?(st.service);
    try R.check(st.graph.import_texture.?(st.graph, abi_render_gpu.c.KE_GPU_INVALID_HANDLE, view, st.output_format, w, h, g.KE_RENDER_GRAPH_USAGE_PRESENT, &st.output));
    st.color = try frameTexture(st, "frame.color", st.color_format);
    st.depth = try frameTexture(st, "frame.depth", st.depth_format);
    var clear_color = use(st.color, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT, g.KE_RENDER_GRAPH_LOAD_CLEAR);
    clear_color.clear_color = st.clear_color;
    var clear_depth = use(st.depth, g.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE, g.KE_RENDER_GRAPH_LOAD_CLEAR);
    clear_depth.clear_depth = 1.0;
    const uses = [_]g.ke_render_graph_use{ clear_color, clear_depth };
    var desc = std.mem.zeroes(g.ke_render_graph_pass_desc);
    desc.name = "frame.clear";
    desc.type = g.KE_RENDER_GRAPH_PASS_RASTER;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = recordNothing;
    desc.user = st;
    var pass: g.ke_render_graph_pass = 0;
    try R.check(st.graph.add_pass.?(st.graph, &desc, &pass));
}

/// The system "render.begin_frame": begins the service's frame and, when the target has a view to
/// draw into, the graph's frame, then publishes the globals and the light. A failure of the service
/// or the graph fails the system with its code and leaves the frame not live.
fn beginSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, dt: f32) callconv(.c) abi_result.c.ke_result {
    const st: *State = @ptrCast(@alignCast(user.?));
    st.live = false;
    st.claimed = false;
    st.color = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    st.depth = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    st.output = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    forgetPublished(st);
    var view: abi_render_gpu.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    const began = st.service.*.begin_frame.?(st.service, &view);
    if (began != R.ok) return began;
    if (view == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) return R.ok;
    declareFrame(st, view) catch |err| {
        log.warn("render frame: the graph refused the frame", .{});
        return R.code(err);
    };
    st.live = true;
    frame_producer.publish(ctx, &st.producer, dt);
    return R.ok;
}

/// Declares the copy of the colour into the output at the tonemap stage, when no pass claimed the
/// output.
fn declarePresent(st: *State) R.Error!void {
    if (st.claimed) return;
    const uses = [_]g.ke_render_graph_use{
        use(st.color, g.KE_RENDER_GRAPH_USAGE_SAMPLED, g.KE_RENDER_GRAPH_LOAD_KEEP),
        use(st.output, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT, g.KE_RENDER_GRAPH_LOAD_DONT_CARE),
    };
    var desc = std.mem.zeroes(g.ke_render_graph_pass_desc);
    desc.name = "frame.present";
    desc.type = g.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_TONEMAP;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = recordBlit;
    desc.user = st;
    var pass: g.ke_render_graph_pass = 0;
    try R.check(st.graph.add_pass.?(st.graph, &desc, &pass));
}

fn executeFrame(st: *State) R.Error!void {
    try declarePresent(st);
    st.service.*.submit_uploads.?(st.service);
    try R.check(st.graph.compile.?(st.graph));
    var done: ?*abi_completion.c.ke_completion = null;
    try R.check(st.graph.execute.?(st.graph, @ptrCast(&done)));
    const completion = done orelse return;
    const waited = completion.wait.?(completion);
    completion.release.?(completion);
    try R.check(waited);
}

/// The system "render.end_frame": copies the colour into the output unless a pass claimed it,
/// submits the uploads, executes
/// the graph and presents. A frame that is not live does nothing. The code of the graph, of a pass's
/// record or of the present fails the system; the target is presented even when the graph failed.
fn endSystem(_: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const st: *State = @ptrCast(@alignCast(user.?));
    if (!st.live) return R.ok;
    st.live = false;
    executeFrame(st) catch |err| {
        log.warn("render frame: the frame could not be executed", .{});
        _ = st.service.*.end_frame.?(st.service);
        return R.code(err);
    };
    return st.service.*.end_frame.?(st.service);
}

/// The `destroy` of the owner `ke_render_frame_systems_create` hands out: unregisters both systems; the frame
/// stays.
fn destroySystems(ref: ?*anyopaque) callconv(.c) void {
    const st: *State = @ptrCast(@alignCast(ref orelse return));
    st.systems.unregister();
}

/// The `destroy` of the frame handle: unregisters its systems and frees the frame.
fn destroyFrame(self: ?*Frame) callconv(.c) void {
    const st = stateOf(self) orelse return;
    st.systems.unregister();
    forgetPublished(st);
    st.published.deinit(gpa);
    gpa.destroy(st);
}

/// The factory declared in frame_create.h. A missing part or settings, or a setting the schema
/// refuses, fails as an invalid argument; the ecs refusing the tag fails with its code; each leaves the handle zeroed.
export fn ke_render_frame_create(ecs: ?*abi_ecs.c.ke_ecs, graph: ?*g.ke_render_graph, service: ?*abi_render.c.ke_render_service, camera: ?*abi_render.c.ke_render_camera, scene: ?*abi_render.c.ke_render_scene_resolve, settings: ?*abi_settings.c.ke_settings, out_frame: ?*abi_render_frame.c.ke_render_frame_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_frame orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const values = settings_schema.read(Settings, settings orelse return refused()) catch |err| return R.code(err);
    const st = create(ecs orelse return refused(), graph orelse return refused(), service orelse return refused(), camera orelse return refused(), scene orelse return refused(), values.color_format.gpu(), values.depth_format.gpu(), values) catch |err| return R.code(err);
    out.* = .{ .ref = &st.api, .destroy = destroyFrame };
    return R.ok;
}

fn refused() abi_result.c.ke_result {
    log.warn("render frame: ecs, graph, service, camera, scene and settings are required", .{});
    return R.code(error.InvalidArgument);
}

fn create(e: *abi_ecs.c.ke_ecs, graph: *g.ke_render_graph, service: *abi_render.c.ke_render_service, camera: *abi_render.c.ke_render_camera, scene: *abi_render.c.ke_render_scene_resolve, color_format: abi_render_gpu.c.ke_gpu_texture_format, depth_format: abi_render_gpu.c.ke_gpu_texture_format, values: Settings) R.Error!*State {
    const st = try gpa.create(State);
    errdefer gpa.destroy(st);
    st.* = .{
        .api = .{
            .handle = st,
            .frame_cid = frameCid,
            .graph = graphOf,
            .live = liveOf,
            .color = colorOf,
            .depth = depthOf,
            .output = outputOf,
            .claim_output = claimOutput,
            .publish = publish,
            .find = find,
            .color_format = colorFormat,
            .depth_format = depthFormat,
            .output_format = outputFormat,
        },
        .graph = graph,
        .service = service,
        .producer = .{ .core = service, .camera = camera },
        .frame_cid = abi_ecs.c.KE_COMPONENT_INVALID,
        .color_format = color_format,
        .depth_format = depth_format,
        .clear_color = values.clear_color,
    };
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_desc{ .name = "render.frame", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &st.frame_cid));

    const ids = scene.render_component_ids.?(scene).?;
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    st.access = .{.{ .component = st.frame_cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    st.query_terms = .{
        .{ .component = ids.*.camera, .access = rd },
        .{ .component = ids.*.world_transform, .access = rd },
        .{ .component = ids.*.directional_light, .access = rd },
        .{ .component = ids.*.ambient_light, .access = rd },
    };
    st.queries = .{
        .{ .terms = st.query_terms[0..].ptr, .term_count = 2 },
        .{ .terms = st.query_terms[2..].ptr, .term_count = 1 },
        .{ .terms = st.query_terms[3..].ptr, .term_count = 1 },
    };
    return st;
}

/// The factory declared in frame_systems_create.h: registers "render.begin_frame" in the begin hook and
/// "render.end_frame" in the submit hook, removing the first when the second is refused. A frame whose systems
/// are registered refuses another registration as not supported.
export fn ke_render_frame_systems_create(
    frame: ?*Frame,
    render_begin: ?*abi_schedule.c.ke_schedule,
    render_begin_set: abi_schedule.c.ke_schedule_set_id,
    render_submit: ?*abi_schedule.c.ke_schedule,
    render_submit_set: abi_schedule.c.ke_schedule_set_id,
    out_systems: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_systems orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const st = stateOf(frame) orelse return R.code(error.InvalidArgument);
    if (st.systems.schedules[0] != null) return R.code(error.NotSupported);
    const registered = st.systems.register(.{
        .{ .name = "render.begin_frame", .execute = beginSystem, .user = st, .hook = 0, .queries = &st.queries, .access = &st.access },
        .{ .name = "render.end_frame", .execute = endSystem, .user = st, .hook = 1, .access = &st.access },
    }, &.{ .{ .schedule = render_begin, .set = render_begin_set }, .{ .schedule = render_submit, .set = render_submit_set } });
    if (registered != R.ok) return registered;
    out.* = .{ .ref = st, .destroy = destroySystems };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_render_frame_create, .{ .name = "render_frame", .slots = &.{"ecs", "graph", "service", "camera", "scene"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_frame").setLogCallback) }),
    part.of(ke_render_frame_systems_create, .{ .name = "render_frame_systems", .slots = &.{"frame"}, .hooks = &.{"render_begin", "render_submit"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_frame").setLogCallback) }),
};

/// The library's parts.
export fn ke_render_frame_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .camera = 1, .world_transform = 2, .directional_light = 3, .ambient_light = 4 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

var completion_released: u32 = 0;

fn completionPoll(_: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
    if (out) |o| o.* = R.ok;
    return true;
}

fn completionWait(_: ?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    return R.ok;
}

fn completionRelease(_: ?*abi_completion.c.ke_completion) callconv(.c) void {
    completion_released += 1;
}

var test_completion: abi_completion.c.ke_completion = .{ .handle = null, .poll = completionPoll, .wait = completionWait, .release = completionRelease };

fn acquireView(args: zsub.For(abi_render.c.ke_render_service).Args(.begin_frame)) abi_result.c.ke_result {
    args[1].?.* = 9;
    return R.ok;
}

fn acquireNothing(args: zsub.For(abi_render.c.ke_render_service).Args(.begin_frame)) abi_result.c.ke_result {
    args[1].?.* = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    return R.ok;
}

fn outputSize(args: zsub.For(abi_render.c.ke_render_service).Args(.backbuffer_size)) void {
    args[1].?.* = 64;
    args[2].?.* = 32;
}

fn executed(args: zsub.For(g.ke_render_graph).Args(.execute)) abi_result.c.ke_result {
    args[1].?.* = &test_completion;
    return R.ok;
}

/// The parts a frame runs on in a test, and what its graph was asked to declare.
const Rig = struct {
    ecs: zsub.For(abi_ecs.c.ke_ecs),
    graph: zsub.For(g.ke_render_graph),
    service: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    camera: abi_render.c.ke_render_camera,
    passes: [4][*:0]const u8,
    pass_count: usize,
    textures: g.ke_render_graph_resource,

    fn init(self: *Rig) !void {
        self.camera = std.mem.zeroes(abi_render.c.ke_render_camera);
        self.passes = undefined;
        self.pass_count = 0;
        self.textures = 10;
        completion_released = 0;
        try self.ecs.init();
        _ = self.ecs.when(.component_register).writesFresh(2);
        try self.graph.init();
        _ = self.graph.when(.import_texture).writes(7, @as(g.ke_render_graph_resource, 1));
        _ = self.graph.when(.create_texture).doesWith(self, createTexture);
        _ = self.graph.when(.add_pass).doesWith(self, addPass);
        _ = self.graph.when(.execute).does(executed);
        try self.service.init();
        _ = self.service.when(.begin_frame).does(acquireView);
        _ = self.service.when(.backbuffer_size).does(outputSize);
        _ = self.service.when(.backbuffer_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM);
        _ = self.service.when(.frame_globals).returns(&zero_globals);
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.schedule.deinit();
        self.service.deinit();
        self.graph.deinit();
        self.ecs.deinit();
    }

    fn createTexture(self: *Rig, args: zsub.For(g.ke_render_graph).Args(.create_texture)) abi_result.c.ke_result {
        self.textures += 1;
        args[2].?.* = self.textures;
        return R.ok;
    }

    fn addPass(self: *Rig, args: zsub.For(g.ke_render_graph).Args(.add_pass)) abi_result.c.ke_result {
        self.passes[self.pass_count] = args[1].?.name.?;
        self.pass_count += 1;
        return R.ok;
    }

    fn frame(self: *Rig, settings: *abi_settings.c.ke_settings) abi_render_frame.c.ke_render_frame_handle {
        var h: abi_render_frame.c.ke_render_frame_handle = .{ .ref = null, .destroy = null };
        _ = ke_render_frame_create(self.ecs.api(), self.graph.api(), self.service.api(), &self.camera, &test_scene, settings, &h);
        return h;
    }

    fn registered(self: *Rig, frame_h: abi_render_frame.c.ke_render_frame_handle) !abi_part.c.ke_owner {
        var m: abi_part.c.ke_owner = undefined;
        try R.check(ke_render_frame_systems_create(frame_h.ref, self.schedule.api(), 1, self.schedule.api(), 4, &m));
        return m;
    }

    fn passNamed(self: *const Rig, name: []const u8) bool {
        for (self.passes[0..self.pass_count]) |p| if (std.mem.eql(u8, std.mem.span(p), name)) return true;
        return false;
    }
};

var zero_globals = std.mem.zeroes(abi_render.c.ke_render_frame_globals);

fn noSegments(_: ?*abi_schedule.c.ke_schedule_ctx, _: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    if (out_count) |c| c.* = 0;
    return null;
}

var empty_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = noSegments, .slice = null };

var no_settings = settings_schema.Fixed.init(&.{});

fn stateOfHandle(h: abi_render_frame.c.ke_render_frame_handle) *State {
    return stateOf(h.ref).?;
}

test "the frame registers its tag, and its systems join the begin and submit hooks and leave with their owner" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    try testing.expect(h.ref.?.frame_cid.?(h.ref) != abi_ecs.c.KE_COMPONENT_INVALID);
    const m = try rig.registered(h);
    try rig.schedule.received(.register_system).times(2);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).sameAs(rig.schedule.received(.register_system));
    h.destroy.?(h.ref);
}

test "frame systems without a submit schedule are refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    var m: abi_part.c.ke_owner = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_frame_systems_create(h.ref, rig.schedule.api(), 1, null, 4, &m));
    try rig.schedule.received(.register_system).never();
}

test "a frame begins the graph at the output's size over the acquired view, and clears its colour and depth" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    try rig.graph.received(.begin_frame).where(zsub.argIs(1, @as(u32, 64))).times(1);
    try rig.graph.received(.import_texture).where(zsub.argIs(2, @as(abi_render_gpu.c.ke_gpu_texture_view, 9))).times(1);
    try testing.expect(h.ref.?.live.?(h.ref));
    try testing.expectEqual(@as(g.ke_render_graph_resource, 1), h.ref.?.output.?(h.ref));
    try testing.expect(h.ref.?.color.?(h.ref) != h.ref.?.output.?(h.ref));
    try testing.expect(h.ref.?.depth.?(h.ref) != h.ref.?.color.?(h.ref));
    try testing.expect(rig.passNamed("frame.clear"));
    try rig.service.received(.set_frame_globals).times(1);
}

test "a frame whose target has nothing to draw into declares, executes and presents nothing" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.service.when(.begin_frame).does(acquireNothing);
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    try testing.expect(!h.ref.?.live.?(h.ref));
    try testing.expectEqual(R.ok, endSystem(null, stateOfHandle(h), 0.016));
    try rig.graph.received(.begin_frame).never();
    try rig.graph.received(.execute).never();
    try rig.service.received(.end_frame).never();
}

test "a frame whose output no pass claimed copies the colour there, then submits the uploads, executes the graph and presents" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    try testing.expectEqual(R.ok, endSystem(null, stateOfHandle(h), 0.016));
    try testing.expect(rig.passNamed("frame.present"));
    try rig.service.received(.submit_uploads).times(1);
    try rig.graph.received(.compile).times(1);
    try rig.graph.received(.execute).times(1);
    try testing.expectEqual(@as(u32, 1), completion_released);
    try rig.service.received(.end_frame).times(1);
}

test "a frame whose output a pass claimed presents without copying the colour" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    h.ref.?.claim_output.?(h.ref);
    try testing.expectEqual(R.ok, endSystem(null, stateOfHandle(h), 0.016));
    try testing.expect(!rig.passNamed("frame.present"));
    try rig.graph.received(.execute).times(1);
}

test "a resource published in a frame is found under its name until the next frame begins" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.frame(&no_settings.api);
    defer h.destroy.?(h.ref);
    const f = h.ref;
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    try R.check(f.?.publish.?(f, "gbuffer.albedo", 5));
    try R.check(f.?.publish.?(f, "gbuffer.albedo", 6));
    try testing.expectEqual(@as(g.ke_render_graph_resource, 6), f.?.find.?(f, "gbuffer.albedo"));
    try testing.expectEqual(g.KE_RENDER_GRAPH_RESOURCE_INVALID, f.?.find.?(f, "shadow.map"));
    try testing.expectEqual(R.ok, beginSystem(&empty_ctx, stateOfHandle(h), 0.016));
    try testing.expectEqual(g.KE_RENDER_GRAPH_RESOURCE_INVALID, f.?.find.?(f, "gbuffer.albedo"));
}

test "a frame missing a part or given an invalid format is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var no_such_format = settings_schema.Fixed.init(&.{.{ .key = "depth_format", .value = .{ .string = "rgba8_unorm" } }});
    try testing.expect(rig.frame(&no_such_format.api).ref == null);
    var h: abi_render_frame.c.ke_render_frame_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_frame_create(rig.ecs.api(), null, rig.service.api(), &rig.camera, &test_scene, &no_settings.api, &h));
    try testing.expect(h.ref == null);
    var out_of_range = settings_schema.Fixed.init(&.{.{ .key = "clear_color.0", .value = .{ .double = 2.0 } }});
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_frame_create(rig.ecs.api(), rig.graph.api(), rig.service.api(), &rig.camera, &test_scene, &out_of_range.api, &h));
    try testing.expect(h.ref == null);
}

test "creating and destroying frames leaves no block allocated" {
    try heap.expectNoLeaks();
}

test "the library's parts name render_frame, render_frame_systems and their slots" {
    var count: usize = 0;
    const all = ke_render_frame_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 2), count);
    try std.testing.expectEqualStrings("render_frame", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[0].name.?));
    try std.testing.expectEqual(@as(usize, 5), @as([*]const abi_part.c.ke_part, @ptrCast(all))[0].slot_count);
    try std.testing.expectEqualStrings("render_frame_systems", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[1].name.?));
    try std.testing.expectEqual(@as(usize, 3), @as([*]const abi_part.c.ke_part, @ptrCast(all))[1].slot_count);
}
