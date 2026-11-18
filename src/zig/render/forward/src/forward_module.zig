//! The transparent forward pass: the system that declares, at the transparent stage, a copy of the
//! frame's color and the pass drawing the blended meshes over that color, sampling the copy for what
//! lies behind them. It also owns the creation and teardown of that pass, behind the one factory it
//! exports.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_forward").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_module = @import("abi_module");
const abi_render = @import("abi_render");
const abi_render_context = @import("abi_render_context");
const abi_render_forward_factory = @import("abi_render_forward_factory");
const abi_render_frame = @import("abi_render_frame");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const abi_spatial = @import("abi_spatial");
const pass_systems = @import("pass_systems");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;
const Features = @import("feature_bindings");
const Groups = @import("material_pass_groups");
const rg = abi_render_graph.c;

/// One draw's transform record, uploaded into that draw's slot of `objects`.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

/// A collected draw. `mesh` and `world` are borrowed pointers into the segment columns that
/// `collectDraws` was given, not copies, so they are valid only while those segments are.
/// `view_distance_sq` is the key `drawFartherFirst` sorts by.
const Draw = struct {
    mesh: *const abi_render_components.c.ke_mesh_component,
    world: *const abi_spatial.c.ke_world_transform_component,
    view_distance_sq: f32,
};

fn drawFartherFirst(_: void, a: Draw, b: Draw) bool {
    return a.view_distance_sq > b.view_distance_sq;
}

/// Called once per frame by `queueSystem` with the segments of its mesh query. Returns how many entries
/// of `out` it filled. Those entries are sorted farthest first, and `record` issues them in that
/// order, so the blend composites back to front.
fn collectDraws(
    core: *abi_render.c.ke_render_service,
    cam: *const abi_render_components.c.ke_camera_component,
    view: zm.Mat,
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
            if (core.material_alpha_mode.?(core, meshes[i].material) != abi_render_handles.c.KE_ALPHA_MODE_BLEND) continue;
            const wm = wts[i].matrix.m;
            const wp = zm.f32x4(wm[12], wm[13], wm[14], 1.0);
            const view_pos = zm.mul(wp, view);
            out.append(gpa, .{ .mesh = @ptrCast(&meshes[i]), .world = @ptrCast(&wts[i]), .view_distance_sq = view_pos[0] * view_pos[0] + view_pos[1] * view_pos[1] + view_pos[2] * view_pos[2] }) catch return false;
        }
    }
    std.sort.pdq(Draw, out.items, {}, drawFartherFirst);
    return true;
}

const Objects = @import("object_uniforms").ObjectUniforms(PerObject);

/// One draw `queueSystem` prepared and `record` issues.
const Prepared = struct {
    pipeline: abi_asset_resolver.c.ke_gpu_pipeline,
    material: abi_asset_resolver.c.ke_render_material_binding,
    vbo: abi_asset_resolver.c.ke_gpu_buffer,
    ibo: abi_asset_resolver.c.ke_gpu_buffer,
    index_count: u32,
    slot: u32,
};

/// The state of one pass. `ke_render_forward_create` allocates it and `destroyHandle` frees it after
/// detaching `systems`. `color`, `copy`, `features`, `env_cubemap` and `prepared` are what
/// `queueSystem` declared this frame, read by the two records; `frame_set` is replaced every frame,
/// since the views it binds are the graph's for that frame.
const ForwardModule = struct {
    systems: pass_systems.Systems(1) = undefined,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,
    frame: *abi_render_frame.c.ke_render_frame = undefined,

    ibl_enabled: bool = true,

    pipeline_template: abi_render_gpu.c.ke_gpu_render_pipeline_desc = undefined,
    attrs: [4]abi_render_gpu.c.ke_gpu_vertex_attribute = undefined,
    vbl: abi_render_gpu.c.ke_gpu_vertex_buffer_layout = undefined,
    groups: Groups = .{},
    frame_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    env_cubemap: abi_render_handles.c.ke_texture_handle = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },
    color: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    copy: rg.ke_render_graph_resource = rg.KE_RENDER_GRAPH_RESOURCE_INVALID,
    features: Features.Published = undefined,

    draws: std.ArrayList(Draw) = .empty,
    prepared: std.ArrayList(Prepared) = .empty,

    access: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries_terms: [5]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [3]abi_ecs.c.ke_ecs_query_desc = undefined,

    /// Loads the vertex and fragment shaders of the pass for the material shader named `shader`
    /// and stores them in `pipeline_template`. `setup` calls it for the default material, and
    /// `queueSystem` calls it for each draw before it fetches that draw's pipeline. Returns false when
    /// a load fails or the name does not fit the buffer it is formatted into. It reports nothing:
    /// `setup` turns the false into an error, and `queueSystem` skips the draw.
    fn resolvePipeline(fwd: *ForwardModule, shader: [*c]const u8) bool {
        var name_buf: [MAX_SHADER_QUALIFIED]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "{s}.{s}", .{ std.mem.span(shader), PASS_NAME }) catch return false;
        var vs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        if (fwd.core.*.load_shader.?(fwd.core, name.ptr, abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &vs) != R.ok) return false;
        var fs: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
        if (fwd.core.*.load_shader.?(fwd.core, name.ptr, abi_render_gpu.c.KE_GPU_SHADER_STAGE_FRAGMENT, &fs) != R.ok) return false;
        fwd.pipeline_template.vertex_module = vs;
        fwd.pipeline_template.fragment_module = fs;
        return true;
    }
};

const PASS_NAME = "forward";
const DEFAULT_MATERIAL_SHADER = "standard";
const MAX_SHADER_QUALIFIED = 128;

const log = std.log.scoped(.render_forward);

inline fn moduleOf(user: ?*anyopaque) *ForwardModule {
    return @alignCast(@ptrCast(user.?));
}

/// Records the copy of the frame's color the transparent draws sample.
fn recordCopy(user: ?*anyopaque, ctx: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const fwd = moduleOf(user);
    fwd.core.*.blit.?(fwd.core, @ptrCast(ctx.?.render_pass.?(ctx)), ctx.?.texture_view.?(ctx, fwd.color), fwd.frame.color_format.?(fwd.frame));
    return R.ok;
}

/// Records the blended draws farthest first. The frame set binds the copy as "hdr_opaque" and the
/// feature bindings, whose environment is the black cube when `ibl_enabled` is false; a set that
/// cannot be created fails with the binder's code.
fn record(user: ?*anyopaque, ctx_in: ?*rg.ke_render_graph_ctx) callconv(.c) abi_result.c.ke_result {
    const fwd = moduleOf(user);
    const core = fwd.core;
    const ctx = ctx_in.?;
    const binder = fwd.groups.binder;
    const env_view = core.*.texture_view.?(core, if (fwd.ibl_enabled) fwd.env_cubemap else .{ .bits = abi_render_handles.c.KE_HANDLE_NONE });
    var bindings: [1 + Features.count]abi_render_gpu.c.ke_render_shader_binding = undefined;
    bindings[0] = .{ .name = "hdr_opaque", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ctx.texture_view.?(ctx, fwd.copy), .sampler = 0 };
    Features.fill(core, ctx, env_view, fwd.features, bindings[1..]);
    binder.destroy_set.?(binder, fwd.frame_set);
    const made = binder.create_set.?(binder, fwd.groups.layout, null, "forward.frame_set", &bindings, bindings.len, &fwd.frame_set);
    if (made != R.ok) {
        log.warn("forward pass: frame set creation failed", .{});
        return made;
    }
    const rp: [*c]abi_render_gpu.c.ke_gpu_render_pass = @ptrCast(ctx.render_pass.?(ctx));
    binder.bind_render_set.?(binder, rp, fwd.frame_set, null, 0);
    const objects = &fwd.objects.?;
    for (fwd.prepared.items) |d| {
        rp.*.set_pipeline.?(rp, d.pipeline);
        fwd.groups.bindMaterial(rp, d.material);
        objects.bind(rp, d.slot);
        rp.*.set_vertex_buffer.?(rp, 0, d.vbo, 0);
        rp.*.set_index_buffer.?(rp, d.ibo, abi_render_gpu.c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, d.index_count, 1, 0, 0, 0);
    }
    return R.ok;
}

fn addPass(graph: *rg.ke_render_graph, name: [*:0]const u8, uses: []const rg.ke_render_graph_use, recorder: rg.ke_render_graph_record_fn, fwd: *ForwardModule) abi_result.c.ke_result {
    var desc = std.mem.zeroes(rg.ke_render_graph_pass_desc);
    desc.name = name;
    desc.type = rg.KE_RENDER_GRAPH_PASS_RASTER;
    desc.injection_point = abi_render.c.KE_RENDER_STAGE_TRANSPARENT;
    desc.uses = uses.ptr;
    desc.use_count = @intCast(uses.len);
    desc.record = recorder;
    desc.user = fwd;
    var pass: rg.ke_render_graph_pass = 0;
    return graph.add_pass.?(graph, &desc, &pass);
}

/// "render.forward_transparent", in the render queue set. A frame not being declared, a render
/// world without a camera, or one with no blended mesh to draw, gets nothing. Otherwise it prepares
/// the draws, writing each one's matrices into the next slot of the shared uniform buffer and
/// skipping one whose geometry or shader is missing, then declares at KE_RENDER_STAGE_TRANSPARENT
/// the copy of the frame's color and the pass drawing over the color, tested against the depth. It
/// fails as out of memory when a list cannot grow, and with the code of the call that failed
/// otherwise.
fn queueSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const fwd = moduleOf(user);
    const core = fwd.core;
    const frame = fwd.frame;
    if (!frame.live.?(frame)) return R.ok;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;
    const cam: *const abi_render_components.c.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));

    const globals = core.*.frame_globals.?(core);
    const view = zm.loadMat(globals.?.view[0..]);
    const view_proj = zm.loadMat(globals.?.view_proj[0..]);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 2, &segc);
    if (segc == 0) return R.ok;
    if (!collectDraws(core, cam, view, segs.?, segc, &fwd.draws)) {
        log.warn("forward pass: draw list allocation failed", .{});
        return R.code(error.OutOfMemory);
    }
    const objects = &fwd.objects.?;
    const grown = objects.ensure(@intCast(fwd.draws.items.len));
    if (grown != R.ok) return grown;
    fwd.prepared.clearRetainingCapacity();
    var slot: u32 = 0;
    for (fwd.draws.items) |draw| {
        var vbo: abi_asset_resolver.c.ke_gpu_buffer = 0;
        var ibo: abi_asset_resolver.c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (!core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count)) continue;
        if (!fwd.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;
        const model = zm.loadMat(draw.world.matrix.m[0..]);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], zm.mul(model, view_proj));
        zm.storeMat(u.model[0..], model);
        core.*.upload.?(core, objects.buffer, Objects.offset(slot), &u, @sizeOf(PerObject));
        fwd.prepared.append(gpa, .{
            .pipeline = core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template),
            .material = core.*.material_binding.?(core, draw.mesh.material),
            .vbo = vbo,
            .ibo = ibo,
            .index_count = idx_count,
            .slot = slot,
        }) catch return R.code(error.OutOfMemory);
        slot += 1;
    }
    if (fwd.prepared.items.len == 0) return R.ok;

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    fwd.env_cubemap = if (sky_segc != 0 and sky_segs.?[0].count != 0)
        (@as(*const abi_render_components.c.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap
    else
        .{ .bits = abi_render_handles.c.KE_HANDLE_NONE };
    fwd.features = Features.find(frame);
    fwd.color = frame.color.?(frame);

    const graph = frame.graph.?(frame).?;
    var desc = std.mem.zeroes(rg.ke_render_graph_texture_desc);
    desc.name = "forward.opaque";
    desc.format = frame.color_format.?(frame);
    desc.size_class = rg.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    desc.mip_levels = 1;
    desc.array_layers = 1;
    desc.samples = 1;
    const made = graph.create_texture.?(graph, &desc, &fwd.copy);
    if (made != R.ok) return made;

    var copy_uses = std.mem.zeroes([2]rg.ke_render_graph_use);
    copy_uses[0].resource = fwd.color;
    copy_uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    copy_uses[1].resource = fwd.copy;
    copy_uses[1].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    copy_uses[1].load = rg.KE_RENDER_GRAPH_LOAD_DONT_CARE;
    const copied = addPass(graph, "forward.opaque", &copy_uses, recordCopy, fwd);
    if (copied != R.ok) return copied;

    var uses = std.mem.zeroes([3 + Features.count]rg.ke_render_graph_use);
    uses[0].resource = fwd.color;
    uses[0].usage = rg.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT;
    uses[1].resource = frame.depth.?(frame);
    uses[1].usage = rg.KE_RENDER_GRAPH_USAGE_DEPTH_READ;
    uses[2].resource = fwd.copy;
    uses[2].usage = rg.KE_RENDER_GRAPH_USAGE_SAMPLED;
    const feature_count = Features.uses(fwd.features, uses[3..]);
    return addPass(graph, "render.forward_transparent", uses[0 .. 3 + feature_count], record, fwd);
}

/// Called once by `ke_render_forward_create` on a module that still has its default fields. It
/// builds the layouts and the pipeline template in the frame's color format, resolves the default
/// material shader and requests one pipeline from it, creates the uniform buffers, and fills the
/// access list and the queries over the render world. On failure it leaves the handles it had
/// already made in the module, where `destroyModule` finds and releases them.
/// The pass's settings, with this implementation's defaults.
const Settings = struct {
    ibl_enabled: bool = true,
};

fn setup(fwd: *ForwardModule, p: *const abi_render_context.c.ke_render_context, config: *const Settings) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    const dev: *abi_render_gpu.c.ke_gpu_device = p.device.?;
    const ids = p.scene.?.render_component_ids.?(p.scene).?;
    fwd.core = core;
    fwd.device = dev;
    fwd.frame = p.frame.?;
    fwd.ibl_enabled = config.ibl_enabled;

    try R.check(fwd.groups.init(core.*.resource_binder.?(core).?, DEFAULT_MATERIAL_SHADER ++ "." ++ PASS_NAME));

    fwd.attrs = [_]abi_render_gpu.c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = abi_render_gpu.c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    fwd.vbl = abi_render_gpu.c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = abi_render_gpu.c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &fwd.attrs,
    };

    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_desc);
    pp.label = "forward.pipeline";
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render_gpu.c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render_gpu.c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render_gpu.c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = (&fwd.vbl)[0..1];
    pp.blend_state.blend_enabled = true;
    pp.blend_state.src_color = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_SRC_ALPHA;
    pp.blend_state.dst_color = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = abi_render_gpu.c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = abi_render_gpu.c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = abi_render_gpu.c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = true;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render_gpu.c.KE_GPU_COMPARE_LESS_EQUAL;
    try R.check(fwd.groups.place(&pp));
    pp.color_target_formats[0] = fwd.frame.color_format.?(fwd.frame);
    pp.color_target_count = 1;
    fwd.pipeline_template = pp;

    if (!fwd.resolvePipeline(DEFAULT_MATERIAL_SHADER)) {
        log.warn("transparent-forward: default material shader failed to load", .{});
        return error.NotInitialized;
    }
    if (core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template) == abi_render_gpu.c.KE_GPU_INVALID_HANDLE) {
        log.warn("transparent-forward: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    fwd.objects = .{ .device = dev, .binder = fwd.groups.binder, .layout = fwd.groups.layout, .buffer_label = "forward.obj_uniform", .set_label = "forward.obj_set" };
    try R.check(fwd.objects.?.ensure(1));

    fwd.access = .{.{ .component = fwd.frame.frame_cid.?(fwd.frame), .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    const rd = abi_ecs.c.KE_ECS_ACCESS_READ;
    fwd.queries_terms = .{ .{ .component = ids.*.camera, .access = rd }, .{ .component = ids.*.world_transform, .access = rd }, .{ .component = ids.*.skybox, .access = rd }, .{ .component = ids.*.mesh, .access = rd }, .{ .component = ids.*.world_transform, .access = rd } };
    fwd.queries = .{ .{ .terms = fwd.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = fwd.queries_terms[2..].ptr, .term_count = 1 }, .{ .terms = fwd.queries_terms[3..].ptr, .term_count = 2 } };
}

/// Releases the sets, buffers and layout the module holds, skipping any still absent, so it also
/// works after a partial `setup`. It does not free the module, and it does not release the
/// pipeline, which `setup` obtained from the render service.
fn destroyModule(fwd: *ForwardModule) void {
    if (fwd.frame_set != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) fwd.groups.binder.destroy_set.?(fwd.groups.binder, fwd.frame_set);
    if (fwd.objects) |*objects| objects.release();
    fwd.draws.deinit(gpa);
    fwd.prepared.deinit(gpa);
    fwd.groups.release();
}

/// The `destroy` slot of the handle that `ke_render_forward_create` returns: detaches the module and
/// frees it with its GPU objects.
fn destroyHandle(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const systems: *pass_systems.Systems(1) = @ptrCast(@alignCast((self orelse return).handle));
    const fwd: *ForwardModule = @fieldParentPtr("systems", systems);
    pass_systems.Systems(1).detach(self);
    destroyModule(fwd);
    gpa.destroy(fwd);
}

/// Factory declared in the plugin's forward_create.h. A missing settings, scene, frame, service or
/// device fails as an invalid argument; a failure in `setup` fails with its code, the module and its
/// GPU objects released.
export fn ke_render_forward_create(context_in: ?*const abi_render_context.c.ke_render_context, settings: ?*abi_settings.c.ke_settings, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const p = context_in orelse return R.code(error.InvalidArgument);
    const values = settings_schema.read(Settings, settings orelse {
        log.warn("transparent-forward: no settings", .{});
        return R.code(error.InvalidArgument);
    }) catch |err| return R.code(err);
    const config = &values;
    if (p.scene == null or p.frame == null or p.service == null or p.device == null)
        return R.code(error.InvalidArgument);

    const fwd = gpa.create(ForwardModule) catch |err| return R.code(err);
    fwd.* = .{};
    setup(fwd, p, config) catch |err| {
        destroyModule(fwd);
        gpa.destroy(fwd);
        return R.code(err);
    };
    fwd.systems.init(.{.{ .name = "render.forward_transparent", .execute = queueSystem, .user = fwd, .set = .queue, .queries = &fwd.queries, .access = &fwd.access }});
    out.* = .{ .ref = &fwd.systems.module, .destroy = destroyHandle };
    return R.ok;
}

const testing = std.testing;

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

fn blendUnlessZero(_: ?*abi_render.c.ke_render_service, m: abi_render_handles.c.ke_material_handle) callconv(.c) abi_render_handles.c.ke_alpha_mode {
    return if (m.bits == 0) abi_render_handles.c.KE_ALPHA_MODE_OPAQUE else abi_render_handles.c.KE_ALPHA_MODE_BLEND;
}

fn blendingService() abi_render.c.ke_render_service {
    var svc = std.mem.zeroes(abi_render.c.ke_render_service);
    svc.material_alpha_mode = blendUnlessZero;
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

fn transformAt(z: f32) abi_spatial.c.ke_world_transform_component {
    var wt = std.mem.zeroes(abi_spatial.c.ke_world_transform_component);
    wt.matrix.m[14] = z;
    return wt;
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
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0b001), out[0].mesh.layers);
}

test "a camera whose mask names several layers draws a mesh on any one of them" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b101);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 2), n);
}

test "a mesh sharing one bit of a multi layer mask is drawn once, not once per bit" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render_components.c.ke_mesh_component{meshOn(0b111)};
    const wts = [_]abi_spatial.c.ke_world_transform_component{transformAt(-1)};
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 1), n);
}

test "a camera that names no layer draws nothing, even with meshes in front of it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 0), n);
}

test "an opaque mesh the camera can see still stays out of the transparent pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    var opaque_mesh = meshOn(0b001);
    opaque_mesh.material = .{ .bits = 0 };
    const meshes = [_]abi_render_components.c.ke_mesh_component{ opaque_mesh, meshOn(0b001) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 7), out[0].mesh.material.bits);
}

test "the culled draws come back farthest first, so blending composites back to front" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-2), transformAt(-9), transformAt(-5) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    const eye_at_origin = zm.lookAtRh(zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 0, -1, 1), zm.f32x4(0, 1, 0, 0));

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, eye_at_origin, &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 3), n);
    try testing.expectEqual(@as(u32, 0b010), out[0].mesh.layers);
    try testing.expectEqual(@as(u32, 0b100), out[1].mesh.layers);
    try testing.expectEqual(@as(u32, 0b001), out[2].mesh.layers);
}

test "draws come back farthest first under a left handed view too" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(2), transformAt(9), transformAt(5) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    const eye_at_origin = zm.lookAtLh(zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 0, 1, 1), zm.f32x4(0, 1, 0, 0));

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, eye_at_origin, &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 3), n);
    try testing.expectEqual(@as(u32, 0b010), out[0].mesh.layers);
    try testing.expectEqual(@as(u32, 0b100), out[1].mesh.layers);
    try testing.expectEqual(@as(u32, 0b001), out[2].mesh.layers);
}

test "every blended mesh is collected, however many there are" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]abi_render_components.c.ke_mesh_component{meshOn(0b001)} ** 600;
    const wts = [_]abi_spatial.c.ke_world_transform_component{transformAt(-1)} ** 600;
    const segs = [_]abi_ecs.c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 600), n);
}

test "meshes are gathered across every segment the query returned" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]abi_render_components.c.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]abi_spatial.c.ke_world_transform_component{transformAt(-1)};
    const b_meshes = [_]abi_render_components.c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]abi_spatial.c.ke_world_transform_component{ transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.c.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 2), n);
}

const zsub = @import("zsub");

var test_camera_component = std.mem.zeroInit(abi_render_components.c.ke_camera_component, .{ .cull_mask = 1 });
var test_meshes = [_]abi_render_components.c.ke_mesh_component{std.mem.zeroInit(abi_render_components.c.ke_mesh_component, .{ .layers = 1, .material = .{ .bits = 7 } })};
var test_transforms = [_]abi_spatial.c.ke_world_transform_component{std.mem.zeroes(abi_spatial.c.ke_world_transform_component)};
var camera_columns = [_]?*anyopaque{ @ptrCast(&test_camera_component), @ptrCast(&test_transforms) };
var mesh_columns = [_]?*anyopaque{ @ptrCast(&test_meshes), @ptrCast(&test_transforms) };
var camera_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &camera_columns, .column_count = 2 };
var mesh_segment: abi_ecs.c.ke_ecs_segment = .{ .entities = null, .count = 1, .columns = &mesh_columns, .column_count = 2 };

fn sceneView(_: ?*abi_schedule.c.ke_schedule_ctx, index: u32, out_count: ?*usize) callconv(.c) ?[*]const abi_ecs.c.ke_ecs_segment {
    out_count.?.* = if (index == 1) 0 else 1;
    return switch (index) {
        0 => (&camera_segment)[0..1],
        2 => (&mesh_segment)[0..1],
        else => null,
    };
}

var scene_ctx: abi_schedule.c.ke_schedule_ctx = .{ .handle = null, .commands = null, .view = sceneView, .slice = null };
var zero_globals = std.mem.zeroes(abi_render.c.ke_render_frame_globals);

fn blendAll(_: zsub.For(abi_render.c.ke_render_service).Args(.material_alpha_mode)) abi_render_handles.c.ke_alpha_mode {
    return abi_render_handles.c.KE_ALPHA_MODE_BLEND;
}

fn meshFound(args: zsub.For(abi_render.c.ke_render_service).Args(.mesh_buffers)) bool {
    args[2].?.* = 1;
    args[3].?.* = 2;
    args[4].?.* = 3;
    return true;
}

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
        _ = self.core.when(.material_alpha_mode).does(blendAll);
        _ = self.core.when(.mesh_buffers).does(meshFound);
        _ = self.core.when(.material_shader).returns("standard");
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.graph.init();
        _ = self.graph.when(.create_texture).writesFresh(2);
        try self.frame.init();
        _ = self.frame.when(.frame_cid).returns(11);
        _ = self.frame.when(.live).returns(true);
        _ = self.frame.when(.color).returns(2);
        _ = self.frame.when(.depth).returns(4);
        _ = self.frame.when(.graph).returns(self.graph.api());
        _ = self.frame.when(.color_format).returns(abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT);
    }

    fn deinit(self: *Rig) void {
        self.frame.deinit();
        self.graph.deinit();
        self.schedule.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn context(self: *Rig) abi_render_context.c.ke_render_context {
        return std.mem.zeroInit(abi_render_context.c.ke_render_context, .{ .scene = &test_scene, .frame = self.frame.api(), .service = self.core.api(), .device = self.dev.api() });
    }

    fn targets(self: *Rig) abi_module.c.ke_module_targets {
        var t = std.mem.zeroes(abi_module.c.ke_module_targets);
        t.render = @ptrCast(self.schedule.api());
        return t;
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

var test_settings = settings_schema.Fixed.init(&.{});

fn passOf(h: abi_module.c.ke_module_handle) *ForwardModule {
    const systems: *pass_systems.Systems(1) = @ptrCast(@alignCast(h.ref.?.handle));
    return @fieldParentPtr("systems", systems);
}

test "the forward module attaches its system to the render schedule, and destroying it detaches it and releases the GPU objects" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_forward_create(&p, &test_settings.api, &h));
    const t = rig.targets();
    try R.check(h.ref.?.attach.?(h.ref, &t));
    try rig.schedule.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rig.schedule.received(.unregister_system).times(1);
    try rig.expectReleased();
}

test "a blended mesh in view gets a copy of the frame's color and a transparent pass over it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_forward_create(&p, &test_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&scene_ctx, passOf(h), 0));
    try rig.graph.received(.create_texture).times(1);
    try rig.graph.received(.add_pass).times(2);
}

test "a frame not being declared gets no transparent pass" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.frame.when(.live).returns(false);
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_forward_create(&p, &test_settings.api, &h));
    defer h.destroy.?(h.ref);
    try testing.expectEqual(R.ok, queueSystem(&scene_ctx, passOf(h), 0));
    try rig.graph.received(.add_pass).never();
}

test "a forward pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    const p = rig.context();
    var h: abi_module.c.ke_module_handle = undefined;
    try testing.expect(ke_render_forward_create(&p, &test_settings.api, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
}

test "a forward pass missing its scene is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var p = rig.context();
    p.scene = null;
    var h: abi_module.c.ke_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_forward_create(&p, &test_settings.api, &h)));
}

test "creating and destroying forward passes leaves no block allocated" {
    try heap.expectNoLeaks();
}
