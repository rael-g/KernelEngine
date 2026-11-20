//! The gbuffer pass: the systems that publish the albedo, normal and emissive targets of a frame and
//! declare, at the prepass stage, the pass rasterising into them and into the frame's depth the
//! opaque meshes a camera sees. It also owns the creation and teardown of that pass, behind the one
//! factory it exports.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_gbuffer").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_part = @import("abi_part");
const abi_render = @import("abi_render");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_spatial = @import("abi_spatial");
const hooked_systems = @import("hooked_systems");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_gbuffer);

const heap = @import("heap");
const gpa = heap.gpa;
const rg = abi_render_graph.c;

/// The suffix `resolvePipeline` appends to a material shader name to pick this pass's variant.
const Groups = @import("material_pass_groups");
const PASS_NAME = "gbuffer";
/// The material shader `setup` loads for the pipeline template; each draw loads its own material's.
const DEFAULT_MATERIAL_SHADER = "standard";

/// One draw's transform record, uploaded into that draw's slot of `objects`. The upload and the
/// object binding both take their size from this type.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

/// A selected mesh and its world transform, as pointers into the query columns rather than copies.
/// They are valid only for the body that collected them.
const Draw = struct {
    mesh: *const abi_render_components.c.ke_mesh_component,
    world: *const abi_spatial.c.ke_world_transform_component,
};

const Objects = @import("object_uniforms").ObjectUniforms(PerObject);

/// Called by `queueSystem` once the camera is known and before any draw is issued. It replaces the
/// contents of `out` with every draw of the body, and returns false when the list cannot grow.
fn collectDraws(
    core: *abi_render.c.ke_render_service,
    cam: *const abi_render_components.c.ke_camera_component,
    segs: [*]const abi_ecs.c.ke_ecs_segment,
    seg_count: usize,
    out: *std.ArrayList(Draw),
) bool {
    out.clearRetainingCapacity();
    var s: usize = 0;
    while (s < seg_count) : (s += 1) {
        const meshes: [*c]const abi_render_components.c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns.?[0]));
        const wts: [*c]const abi_spatial.c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (meshes[i].layers & cam.cull_mask == 0) continue;
            if (core.material_alpha_mode.?(core, meshes[i].material) == abi_render_handles.c.KE_ALPHA_MODE_BLEND) continue;
            out.append(gpa, .{ .mesh = @ptrCast(&meshes[i]), .world = @ptrCast(&wts[i]) }) catch return false;
        }
    }
    return true;
}

const target_formats = [3]abi_render_gpu.c.ke_gpu_texture_format{ abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT };
const target_names = [3][*:0]const u8{ abi_render.c.KE_RENDER_RESOURCE_GBUFFER_ALBEDO, abi_render.c.KE_RENDER_RESOURCE_GBUFFER_NORMAL, abi_render.c.KE_RENDER_RESOURCE_GBUFFER_EMISSIVE };

/// One draw `queueSystem` prepared and `record` issues: the pipeline, the material and the geometry,
/// and the slot of `objects` holding its matrices.
const Prepared = struct {
    pipeline: abi_asset_resolver.c.ke_gpu_pipeline,
    material: abi_asset_resolver.c.ke_render_material_binding,
    vbo: abi_asset_resolver.c.ke_gpu_buffer,
    ibo: abi_asset_resolver.c.ke_gpu_buffer,
    index_count: u32,
    slot: u32,
};

/// The state of one gbuffer pass, allocated by `ke_render_gbuffer_create` and freed by
/// `destroyOwner` after it unregisters `systems`. Handles start as KE_GPU_INVALID_HANDLE and are filled
/// by `setup`, which is what lets `destroyModule` release a module whose setup stopped partway.
/// `targets` are the frame's, made by `prepareSystem`; `prepared` is rebuilt by `queueSystem` and
/// read by `record`.
const GBufferModule = struct {
    systems: hooked_systems.Systems(2) = .{},
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,

    targets: [3]rg.ke_render_graph_resource = .{ 0, 0, 0 },

    pipeline_template: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    attrs: [4]abi_render_gpu.c.ke_gpu_vertex_attribute = undefined,
    vbl: abi_render_gpu.c.ke_gpu_vertex_buffer_layout = undefined,
    groups: Groups = .{},
    frame_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    draws: std.ArrayList(Draw) = .empty,
    prepared: std.ArrayList(Prepared) = .empty,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [4]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [2]abi_ecs.c.ke_ecs_query_desc = undefined,

    /// Loads the vertex and fragment stages of the given material shader under this pass's name,
    /// and stores both in `pipeline_template` only when both loads succeed, so a false return
    /// leaves the template as it was. `setup` calls it for the default material and `queueSystem`
    /// for each draw.
    fn resolvePipeline(gb: *GBufferModule, shader: [*c]const u8) bool {
        var name_buf: [rc_MAX_SHADER_QUALIFIED]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "{s}.{s}", .{ std.mem.span(shader), PASS_NAME }) catch return false;
        var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        if (gb.core.*.load_shader.?(gb.core, name.ptr, abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs) != R.ok) return false;
        var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        if (gb.core.*.load_shader.?(gb.core, name.ptr, abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs) != R.ok) return false;
        gb.pipeline_template.vertex_module = vs;
        gb.pipeline_template.fragment_module = fs;
        return true;
    }
};

/// The size of the buffer `resolvePipeline` formats the qualified shader name into. A longer name
/// fails the load.
const rc_MAX_SHADER_QUALIFIED = 128;

inline fn moduleOf(user: ?*anyopaque) *GBufferModule {
    return @alignCast(@ptrCast(user.?));
}

/// "render.gbuffer.targets", in the render prepare set: makes the three targets the size of the
/// frame's output and publishes them. A frame not being declared gets none; the graph or the frame
/// refusing one fails with its code.
fn prepareSystem(_: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const gb = moduleOf(user);
    const frame = gb.frame;
    if (!frame.live.?(frame)) return R.ok;
    const graph = frame.graph.?(frame).?;
    for (target_names, target_formats, &gb.targets) |name, format, *target| {
        var desc = std.mem.zeroes(rg.ke_render_graph_texture_desc);
        desc.name = name;
        desc.format = format;
        desc.size_class = rg.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE;
        desc.scale_x = 1.0;
        desc.scale_y = 1.0;
        desc.mip_levels = 1;
        desc.array_layers = 1;
        desc.samples = 1;
        const made = graph.create_texture.?(graph, &desc, target);
        if (made != R.ok) return made;
        const published = frame.publish.?(frame, name, target.*);
        if (published != R.ok) return published;
    }
    return R.ok;
}

/// Records the draws `queueSystem` prepared, binding each one's matrices by dynamic offset.
fn record(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const gb = moduleOf(user);
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.?.render_pass.?(ctx));
    gb.groups.binder.bind_render_set.?(gb.groups.binder, rp, gb.frame_set, null, 0);
    const objects = &gb.objects.?;
    for (gb.prepared.items) |d| {
        rp.*.set_pipeline.?(rp, d.pipeline);
        gb.groups.bindMaterial(rp, d.material);
        objects.bind(rp, d.slot);
        rp.*.set_vertex_buffer.?(rp, 0, d.vbo, 0);
        rp.*.set_index_buffer.?(rp, d.ibo, abi_render_gpu.c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, d.index_count, 1, 0, 0, 0);
    }
    return R.ok;
}

/// "render.gbuffer", in the render queue set. A frame not being declared, or a render world with no
/// camera, gets no pass. Otherwise it prepares the draws `collectDraws` selects: those on a layer the
/// camera's cull mask names, minus the blended ones. A draw writes its matrices into the next slot of
/// the one shared uniform buffer; a draw whose geometry or shader is missing is skipped without
/// consuming a slot. It then declares at KE_RENDER_STAGE_PREPASS the pass clearing and writing the
/// three targets and writing the frame's depth, recorded even when nothing is drawn. It fails as out
/// of memory when a list cannot grow, and with the code of the call that failed otherwise.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const gb = moduleOf(user);
    const core = gb.core;
    const frame = gb.frame;
    if (!frame.live.?(frame)) return R.ok;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;

    const cam: *const abi_render_components.c.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));
    const view_proj = zm.loadMat(core.*.frame_globals.?(core).?.view_proj[0..]);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    const objects = &gb.objects.?;
    gb.prepared.clearRetainingCapacity();
    if (segc > 0) {
        if (!collectDraws(core, cam, segs.?, segc, &gb.draws)) {
            log.warn("gbuffer pass: draw list allocation failed", .{});
            return R.code(error.OutOfMemory);
        }
        const grown = objects.ensure(@intCast(gb.draws.items.len));
        if (grown != R.ok) return grown;
        var slot: u32 = 0;
        for (gb.draws.items) |draw| {
            var vbo: abi_asset_resolver.c.ke_gpu_buffer = 0;
            var ibo: abi_asset_resolver.c.ke_gpu_buffer = 0;
            var idx_count: u32 = 0;
            if (!core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count)) continue;
            if (!gb.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;

            const model = zm.loadMat(draw.world.matrix.m[0..]);
            const mvp = zm.mul(model, view_proj);
            var u: PerObject = undefined;
            zm.storeMat(u.mvp[0..], mvp);
            zm.storeMat(u.model[0..], model);
            core.*.upload.?(core, objects.buffer, Objects.offset(slot), &u, @sizeOf(PerObject));
            gb.prepared.append(gpa, .{
                .pipeline = core.*.get_or_create_pipeline.?(core, &gb.pipeline_template),
                .material = core.*.material_binding.?(core, draw.mesh.material),
                .vbo = vbo,
                .ibo = ibo,
                .index_count = idx_count,
                .slot = slot,
            }) catch return R.code(error.OutOfMemory);
            slot += 1;
        }
    }

    var uses = std.mem.zeroes([4]rg.ke_render_graph_use);
    for (gb.targets, 0..) |target, i| {
        uses[i].resource = target;
        uses[i].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
        uses[i].load = rg.KE_RENDER_GRAPH_LOAD_CLEAR;
    }
    uses[3].resource = frame.depth.?(frame);
    uses[3].usage = rg.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE;
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = "render.gbuffer";
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_PREPASS;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = record;
    desc.user = gb;
    const graph = frame.graph.?(frame).?;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// Called once by `ke_render_gbuffer_create`. It creates the GPU objects and fills
/// `pipeline_template`, `access` and `queries` over the render world, and it requests the pipeline
/// now, so a failure there fails creation instead of the first frame. On failure the module keeps
/// the handles it made for `destroyModule`.
fn setup(gb: *GBufferModule, service: *abi_render.c.ke_render_service, device: *abi_render_gpu.c.ke_gpu_device, frame: *abi_render_frame.c.ke_render_frame, scene: *abi_render.c.ke_render_scene_resolve) R.Error!void {
    const core: *abi_render.c.ke_render_service = service;
    const dev: *abi_render_gpu.c.ke_gpu_device = device;
    const ids = scene.render_component_ids.?(scene).?;
    gb.core = core;
    gb.device = dev;
    gb.frame = frame;

    const binder: *abi_render_gpu.c.ke_render_resource_binder = core.*.resource_binder.?(core).?;
    try R.check(gb.groups.init(binder, DEFAULT_MATERIAL_SHADER ++ "." ++ PASS_NAME));
    try R.check(binder.create_set.?(binder, gb.groups.layout, null, "gbuffer.frame_set", null, 0, &gb.frame_set));

    gb.attrs = [_]abi_render_gpu.c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    gb.vbl = abi_render_gpu.c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = abi_render_gpu.c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &gb.attrs,
    };

    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    pp.label = "gbuffer.pipeline";
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = (&gb.vbl)[0..1];
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = true;
    pp.depth_stencil.depth_write_enabled = true;
    pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_LESS;
    try R.check(gb.groups.place(&pp));
    for (target_formats, 0..) |format, i| pp.color_target_formats[i] = format;
    pp.color_target_count = 3;
    gb.pipeline_template = pp;

    if (!gb.resolvePipeline(DEFAULT_MATERIAL_SHADER)) {
        log.warn("gbuffer pass: default material shader failed to load", .{});
        return error.NotInitialized;
    }
    if (core.*.get_or_create_pipeline.?(core, &gb.pipeline_template) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("gbuffer pass: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    gb.objects = .{ .device = dev, .binder = binder, .layout = gb.groups.layout, .buffer_label = "gbuffer.obj_uniform", .set_label = "gbuffer.obj_set" };
    try R.check(gb.objects.?.ensure(1));

    gb.access = .{.{ .component = gb.frame.frame_cid.?(gb.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    gb.queries_terms = .{ .{ .component = ids.*.camera, .access = rd }, .{ .component = ids.*.world_transform, .access = rd }, .{ .component = ids.*.mesh, .access = rd }, .{ .component = ids.*.world_transform, .access = rd } };
    gb.queries = .{ .{ .terms = gb.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = gb.queries_terms[2..].ptr, .term_count = 2 } };
}

/// Releases the GPU objects and sets `setup` created, skipping any still invalid, so it also serves a
/// module whose setup stopped partway. Used on creation failure and by `destroyOwner`.
fn destroyModule(gb: *GBufferModule) void {
    if (gb.objects) |*objects| objects.release();
    gb.draws.deinit(gpa);
    gb.prepared.deinit(gpa);
    if (gb.frame_set != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) gb.groups.binder.destroy_set.?(gb.groups.binder, gb.frame_set);
    gb.groups.release();
}

/// The `destroy` of the owner `ke_render_gbuffer_create` hands out: unregisters the systems, releases the GPU
/// objects and frees the pass; a null argument is ignored.
fn destroyOwner(ref: ?*anyopaque) callconv(.c) void {
    const gb: *GBufferModule = @ptrCast(@alignCast(ref orelse return));
    gb.systems.unregister();
    destroyModule(gb);
    gpa.destroy(gb);
}

/// The factory the plugin exports, declared in the plugin's factory header. A missing scene, frame,
/// render service or device fails as an invalid argument and a failed allocation as out of memory.
/// A failing setup fails with its code and leaves the handle zeroed after releasing the module.
export fn ke_render_gbuffer_create(
    service_in: ?*abi_render.c.ke_render_service,
    device_in: ?*abi_render_gpu.c.ke_gpu_device,
    frame_in: ?*abi_render_frame.c.ke_render_frame,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    render_prepare: ?*abi_schedule.c.ke_schedule,
    render_prepare_set: abi_schedule.c.ke_schedule_set_id,
    render_queue: ?*abi_schedule.c.ke_schedule,
    render_queue_set: abi_schedule.c.ke_schedule_set_id,
    out_pass: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_pass orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const service = service_in orelse return R.code(error.InvalidArgument);
    const device = device_in orelse return R.code(error.InvalidArgument);
    const frame = frame_in orelse return R.code(error.InvalidArgument);
    const scene = scene_in orelse return R.code(error.InvalidArgument);
    if (render_prepare == null) return R.code(error.InvalidArgument);
    if (render_queue == null) return R.code(error.InvalidArgument);

    const gb = gpa.create(GBufferModule) catch |err| return R.code(err);
    gb.* = .{};
    setup(gb, service, device, frame, scene) catch |err| {
        destroyModule(gb);
        gpa.destroy(gb);
        return R.code(err);
    };
    const registered = gb.systems.register(.{
        .{ .name = "render.gbuffer.targets", .execute = prepareSystem, .user = gb, .hook = 0, .access = &gb.access },
        .{ .name = "render.gbuffer", .execute = queueSystem, .user = gb, .hook = 1, .queries = &gb.queries, .access = &gb.access },
    }, &.{ .{ .schedule = render_prepare, .set = render_prepare_set }, .{ .schedule = render_queue, .set = render_queue_set } });
    if (registered != R.ok) {
        destroyModule(gb);
        gpa.destroy(gb);
        return registered;
    }
    out.* = .{ .ref = gb, .destroy = destroyOwner };
    return R.ok;
}

const testing = std.testing;

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

fn opaqueUnlessZero(_: ?*abi_render.c.ke_render_service, m: abi_render_handles.c.ke_material_handle) callconv(.c) abi_render_handles.c.ke_alpha_mode {
    return if (m.bits == 0) abi_render_handles.c.KE_ALPHA_MODE_BLEND else abi_render_handles.c.KE_ALPHA_MODE_OPAQUE;
}

fn opaqueService() abi_render.c.ke_render_service {
    var svc = std.mem.zeroes(abi_render.c.ke_render_service);
    svc.material_alpha_mode = opaqueUnlessZero;
    return svc;
}

fn cameraSeeing(mask: u32) abi_render_components.c.ke_camera_component {
    var cam = std.mem.zeroes(abi_render_components.c.ke_camera_component);
    cam.cull_mask = mask;
    return cam;
}

fn meshOn(layers: u32) abi_render_components.c.ke_mesh_component {
    var m = std.mem.zeroes(abi_render_components.c.ke_mesh_component);
    m.layers = layers;
    m.material = .{ .bits = 7 };
    return m;
}

var column_pool: [8][2]?*anyopaque = undefined;
var column_pool_next: usize = 0;

fn oneSegment(meshes: []const abi_render_components.c.ke_mesh_component, wts: []const abi_spatial.c.ke_world_transform_component) abi_ecs.c.ke_ecs_segment {
    var seg = std.mem.zeroes(abi_ecs.c.ke_ecs_segment);
    const cols = &column_pool[column_pool_next % column_pool.len];
    column_pool_next += 1;
    cols[0] = @constCast(@ptrCast(meshes.ptr));
    cols[1] = @constCast(@ptrCast(wts.ptr));
    seg.columns = cols[0..].ptr;
    seg.column_count = 2;
    seg.count = meshes.len;
    return seg;
}

test "a mesh on a layer the camera's cull_mask omits is not drawn" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = opaqueService();
    const cam = cameraSeeing(0b010);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)} ** 3;
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));

    try testing.expectEqual(@as(usize, 1), out.items.len);
    try testing.expectEqual(@as(u32, 0b010), out.items[0].mesh.layers);
}

test "a camera that names no layer draws nothing into the gbuffer" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = opaqueService();
    const cam = cameraSeeing(0);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)} ** 2;
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 0), out.items.len);
}

test "a blending mesh the camera can see is left to the forward pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    var blended = meshOn(0b001);
    blended.material = .{ .bits = 0 };
    const meshes = [_]abi_render_components.c.ke_mesh_component{ blended, meshOn(0b001) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)} ** 2;
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));

    try testing.expectEqual(@as(usize, 1), out.items.len);
    try testing.expectEqual(@as(u32, 7), out.items[0].mesh.material.bits);
}

test "every visible mesh is collected, however many there are" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]abi_render_components.c.ke_mesh_component{meshOn(0b001)} ** 600;
    const wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)} ** 600;
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 600), out.items.len);
}

test "meshes are gathered across every segment the query returned" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]abi_render_components.c.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)};
    const b_meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)} ** 2;
    const segs = [_]abi_ecs.c.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 2), out.items.len);
}

const zsub = @import("zsub");

var test_camera_component = std.mem.zeroes(abi_render_components.c.ke_camera_component);
var camera_columns = [_]?*anyopaque{ @ptrCast(&test_camera_component), @ptrCast(&test_camera_component) };
var camera_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &camera_columns, .column_count = 2 };

fn cameraView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = if (index == 0) 1 else 0;
    return if (index == 0) (&camera_segment)[0..1] else null;
}

var camera_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = cameraView, .slice = null };
var empty_ctx: abi_schedule.c.ke_schedule_ctx = std.mem.zeroes(abi_schedule.c.ke_schedule_ctx);
var zero_globals = std.mem.zeroes(abi_render.c.ke_render_frame_globals);

/// The parts a pass is made of in a test.
const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    frame: zsub.For(abi_render_frame.c.ke_render_frame),
    graph: zsub.For(rg.ke_render_graph),

    fn init(self: *Rig) !void {
        try self.dev.init();
        _ = self.dev.when(.create_buffer).writesFresh(2);
        try self.binder.init();
        _ = self.binder.when(.create_shader_layout).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
        try self.core.init();
        _ = self.core.when(.resource_binder).returns(self.binder.api());
        _ = self.core.when(.material_binding).returnsFresh();
        _ = self.core.when(.load_shader).writesFresh(3);
        _ = self.core.when(.get_or_create_pipeline).returnsFresh();
        _ = self.core.when(.texture_view).returnsFresh();
        _ = self.core.when(.frame_globals).returns(&zero_globals);
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        _ = self.graph.when(.create_texture).writesFresh(2);
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.depth).returns(4);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.depth_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn create(self: *Rig, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_gbuffer_create(self.core.api(), self.dev.api(), self.frame.api(), &test_scene, self.schedule.api(), 4, self.schedule.api(), 5, out);
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

fn passOf(h: abi_part.c.ke_owner) *GBufferModule {
    return @ptrCast(@alignCast(h.ref.?));
}

test "the gbuffer pass registers its two systems in its hooks, and destroying it unregisters them and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    try rig.schedule.received(.register_system).times(2);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(2);
    try rig.expectReleased();
}

test "the gbuffer publishes its three targets each frame, and declares its pass at the prepass stage when a camera sees" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, prepareSystem(&empty_ctx, passOf(h), 0));
    try rig.graph.received(.create_texture).times(3);
    try rig.frame.received(.publish).times(3);
    try testing.expectEqual(R.ok, queueSystem(&camera_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).times(1);
}

test "a frame not being declared gets no gbuffer" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.live).returns(false);
    var h: abi_part.c.ke_owner = undefined;
    try R.check(rig.create(&h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, prepareSystem(&empty_ctx, passOf(h), 0));
    try testing.expectEqual(R.ok, queueSystem(&camera_ctx, passOf(h), 0));
    try rig.graph.received(.create_texture).never();
    try rig.graph.received(.add_pass).never();
}

test "a gbuffer pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_part.c.ke_owner = undefined;
    try testing.expect(rig.create(&h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a gbuffer pass missing its scene is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_gbuffer_create(rig.core.api(), rig.dev.api(), rig.frame.api(), null, rig.schedule.api(), 4, rig.schedule.api(), 5, &h)));
}

test "creating and destroying gbuffer passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
