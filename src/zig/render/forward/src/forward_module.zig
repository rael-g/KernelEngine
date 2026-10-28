//! The transparent forward pass: the render-phase system that draws the blended meshes over a copy
//! of the frame's color, at the chain's transparent stage. It also owns the creation and teardown of that pass, behind the one
//! factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_forward").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_forward_factory = @import("abi_render_forward_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});

const heap = @import("heap");
const gpa = heap.gpa;
const Features = @import("feature_bindings");
const Groups = @import("material_pass_groups");

/// One draw's transform record, uploaded into that draw's slot of `objects`.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

/// A collected draw. `mesh` and `world` are borrowed pointers into the segment columns that
/// `collectDraws` was given, not copies, so they are valid only while those segments are.
/// `view_distance_sq` is the key `drawFartherFirst` sorts by.
const Draw = struct {
    mesh: *const abi_render.ke_mesh_component,
    world: *const abi_spatial.ke_world_transform_component,
    view_distance_sq: f32,
};

fn drawFartherFirst(_: void, a: Draw, b: Draw) bool {
    return a.view_distance_sq > b.view_distance_sq;
}

/// Called once per frame by `system` with the segments of its mesh query. Returns how many entries
/// of `out` it filled. Those entries are sorted farthest first, and `system` records them in that
/// order, so the blend composites back to front.
fn collectDraws(
    core: *abi_render.ke_render_service,
    cam: *const abi_render.ke_camera_component,
    view: zm.Mat,
    segs: [*]const abi_ecs.ke_ecs_segment,
    seg_count: usize,
    out: *std.ArrayList(Draw),
) bool {
    out.clearRetainingCapacity();
    var s: usize = 0;
    while (s < seg_count) : (s += 1) {
        const meshes: [*c]const abi_render.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns.?[0]));
        const wts: [*c]const abi_spatial.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns.?[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (meshes[i].layers & cam.cull_mask == 0) continue;
            if (core.material_alpha_mode.?(core, meshes[i].material) != abi_render.KE_ALPHA_MODE_BLEND) continue;
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

/// The state of one pass. `ke_render_forward_create` allocates it on the heap and `destroyHandle`
/// frees it, and nothing else takes ownership. `core` and `device` are borrowed for its
/// whole life and never released here. The GPU objects are made by `setup` and released by
/// `destroyModule`, and `frame_set` is replaced whenever the environment cubemap changes or
/// the declared targets are recreated.
/// Several fields point into the struct itself, so it must not be moved after `setup`.
const ForwardModule = struct {
    core: *abi_render.ke_render_service = undefined,
    device: *abi_render.ke_gpu_device = undefined,

    ibl_enabled: bool = true,

    mesh_cid: abi_ecs.ke_component_id = undefined,
    world_transform_cid: abi_ecs.ke_component_id = undefined,
    camera_cid: abi_ecs.ke_component_id = undefined,
    skybox_cid: abi_ecs.ke_component_id = undefined,

    shadow: ?[:0]u8 = null,
    clusters: ?[:0]u8 = null,

    pipeline_template: abi_render.ke_gpu_render_pipeline_params = undefined,
    attrs: [4]abi_render.ke_gpu_vertex_attribute = undefined,
    vbl: abi_render.ke_gpu_vertex_buffer_layout = undefined,
    groups: Groups = .{},
    frame_set: abi_render.ke_render_resource_set = abi_render.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    env_cubemap: abi_render.ke_texture_handle = .{ .bits = abi_render.KE_HANDLE_NONE },
    resource_generation: u32 = 0,
    opaque_view: abi_render.ke_gpu_texture_view = abi_render.KE_GPU_INVALID_HANDLE,

    draws: std.ArrayList(Draw) = .empty,

    io: abi_render.ke_render_pass_io = std.mem.zeroes(abi_render.ke_render_pass_io),
    access: [10]abi_runtime.ke_component_access = undefined,
    access_count: u32 = 0,
    queries_terms: [5]abi_runtime.ke_component_access = undefined,
    queries: [3]abi_runtime.ke_query_decl = undefined,

    /// Loads the vertex and fragment shaders of the pass for the material shader named `shader`
    /// and stores them in `pipeline_template`. `setup` calls it for the default material, and
    /// `system` calls it for each draw before it fetches that draw's pipeline. Returns false when
    /// a load fails or the name does not fit the buffer it is formatted into. It reports nothing:
    /// `setup` turns the false into an error, and `system` skips the draw.
    fn resolvePipeline(fwd: *ForwardModule, shader: [*c]const u8) bool {
        var name_buf: [MAX_SHADER_QUALIFIED]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "{s}.{s}", .{ std.mem.span(shader), PASS_NAME }) catch return false;
        var vs: abi_render.ke_gpu_shader_module = undefined;
        if (fwd.core.*.load_shader.?(fwd.core, name.ptr, abi_render.KE_GPU_SHADER_STAGE_VERTEX, &vs) != R.ok) return false;
        var fs: abi_render.ke_gpu_shader_module = undefined;
        if (fwd.core.*.load_shader.?(fwd.core, name.ptr, abi_render.KE_GPU_SHADER_STAGE_FRAGMENT, &fs) != R.ok) return false;
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

/// Replaces `frame_set` with a set over `opaque_view`, sampled as "hdr_opaque", and the feature
/// bindings, whose environment is the black cube when `ibl_enabled` is false. `setup` calls it once
/// over the white texture, and `system` calls it when the skybox's cubemap or the color source of
/// the link changes, or the service recreated its declared targets. The set it replaces is
/// destroyed. A creation failure is logged, and `frame_set` is then invalid.
fn rebuildFrameSet(fwd: *ForwardModule) void {
    const core = fwd.core;
    const binder = fwd.groups.binder;
    const env_view = core.*.texture_view.?(core, fwd.env_cubemap);
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = abi_render.KE_HANDLE_NONE });
    const ibl_view = if (fwd.ibl_enabled) env_view else black_cube_view;

    var bindings: [1 + Features.count]abi_render.ke_render_shader_binding = undefined;
    bindings[0] = .{ .name = "hdr_opaque", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = fwd.opaque_view, .sampler = 0 };
    Features.fill(core, ibl_view, nameOf(fwd.shadow), nameOf(fwd.clusters), bindings[1..]);

    binder.destroy_set.?(binder, fwd.frame_set);
    fwd.resource_generation = core.*.resource_generation.?(core);
    if (binder.create_set.?(binder, fwd.groups.layout, null, "forward.frame_set", &bindings, bindings.len, &fwd.frame_set) != R.ok)
        log.err("transparent-forward frame set creation failed", .{});
}

/// The render-phase system that `ke_render_forward_create` registers, with no pinned worker. It
/// fails as out of memory when the draw list cannot grow, and with the code of the call that
/// failed when the per-draw uniforms cannot. Once
/// `begin_pass` has returned a pass context, every path reaches `end_pass`. A scene without a
/// camera does nothing. Otherwise it draws over a copy of the frame's color, whose source the
/// blended materials sample for what lies behind them, and it keeps `frame_set` matching the sky
/// and that source. The view and the
/// projection come from the frame globals the service holds. A draw whose geometry or shader is missing is skipped.
fn system(ctx: ?*abi_runtime.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.ke_result {
    const fwd = moduleOf(user);
    const core = fwd.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs.?[0].count == 0) return R.ok;

    const cam: *const abi_render.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));

    const pc = core.*.begin_pass.?(core, &fwd.io);
    if (pc == null) return R.ok;

    const globals = core.*.frame_globals.?(core);
    const view = zm.loadMat(globals.?.view[0..]);
    const view_proj = zm.loadMat(globals.?.view_proj[0..]);

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const want_env: abi_render.ke_texture_handle = if (sky_segc != 0 and sky_segs.?[0].count != 0)
        (@as(*const abi_render.ke_skybox_component, @ptrCast(@alignCast(sky_segs.?[0].columns.?[0])))).cubemap
    else
        .{ .bits = abi_render.KE_HANDLE_NONE };
    const opaque_view = pc.?.color_source.?(pc);
    if (want_env.bits != fwd.env_cubemap.bits or fwd.frame_set == abi_render.KE_RENDER_BINDING_INVALID or
        fwd.resource_generation != core.*.resource_generation.?(core) or opaque_view != fwd.opaque_view)
    {
        fwd.env_cubemap = want_env;
        fwd.opaque_view = opaque_view;
        rebuildFrameSet(fwd);
    }

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 2, &segc);
    const objects = &fwd.objects.?;
    if (!collectDraws(core, cam, view, segs.?, segc, &fwd.draws)) {
        log.warn("forward pass: draw list allocation failed", .{});
        core.*.end_pass.?(core, pc);
        return R.code(error.OutOfMemory);
    }
    const grown = objects.ensure(@intCast(fwd.draws.items.len));
    if (grown != R.ok) {
        core.*.end_pass.?(core, pc);
        return grown;
    }

    const rp = pc.?.begin_render.?(pc);
    fwd.groups.binder.bind_render_set.?(fwd.groups.binder, rp, fwd.frame_set, null, 0);

    for (fwd.draws.items, 0..) |draw, i| {
        const d: u32 = @intCast(i);
        var vbo: abi_render.ke_gpu_buffer = 0;
        var ibo: abi_render.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (!core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count)) continue;

        if (!fwd.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;
        rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template));

        const model = zm.loadMat(draw.world.matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        const offset: u32 = Objects.offset(d);
        core.*.upload.?(core, objects.buffer, offset, &u, @sizeOf(PerObject));

        fwd.groups.bindMaterial(rp, core.*.material_binding.?(core, draw.mesh.material));
        objects.bind(rp, d);
        rp.?.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.?.set_index_buffer.?(rp, ibo, abi_render.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.?.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_forward_create` on a module that still has its default fields. It
/// copies the group names, joins the chain at the transparent stage, builds the layouts
/// and the pipeline template, resolves the default material shader and requests one pipeline from
/// it, creates the uniform buffers, and fills the pass io, the access list and the queries. On
/// failure it leaves the handles it had already made in the module, where `destroyModule` finds and releases them.
/// Joining, it tells the runtime that the chain, not the runtime, orders the writers of the
/// frame's color.
fn setup(fwd: *ForwardModule, p: *const abi_render_forward_factory.ke_render_forward_params) R.Error!void {
    const core: *abi_render.ke_render_service = p.service.?;
    const dev: *abi_render.ke_gpu_device = p.device.?;
    const mesh_cid = p.mesh_cid;
    const world_transform_cid = p.world_transform_cid;
    const camera_cid = p.camera_cid;
    const skybox_cid = p.skybox_cid;
    const frame_cid = p.frame_cid;
    fwd.core = core;
    fwd.device = dev;
    fwd.ibl_enabled = p.ibl_enabled;
    fwd.mesh_cid = mesh_cid;
    fwd.world_transform_cid = world_transform_cid;
    fwd.camera_cid = camera_cid;
    fwd.skybox_cid = skybox_cid;
    fwd.env_cubemap = .{ .bits = abi_render.KE_HANDLE_NONE };

    if (p.shadow != null) fwd.shadow = try gpa.dupeZ(u8, std.mem.span(p.shadow.?));
    if (p.clusters != null) fwd.clusters = try gpa.dupeZ(u8, std.mem.span(p.clusters.?));
    fwd.io.name = "render.forward_transparent";
    fwd.io.depth = abi_render.KE_RENDER_DEPTH_TEST;
    try R.check(core.*.join_chain.?(core, abi_render.KE_RENDER_STAGE_TRANSPARENT, abi_render.KE_RENDER_CHAIN_SAMPLE_OVER, &fwd.io.chain));
    try R.check(p.runtime.?.declare_self_ordered.?(p.runtime, core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR)));

    try R.check(fwd.groups.init(core.*.resource_binder.?(core).?, DEFAULT_MATERIAL_SHADER ++ "." ++ PASS_NAME));

    fwd.attrs = [_]abi_render.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = abi_render.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    fwd.vbl = abi_render.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = abi_render.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &fwd.attrs,
    };

    var pp = std.mem.zeroes(abi_render.ke_gpu_render_pipeline_params);
    pp.label = "forward.pipeline";
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = abi_render.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = abi_render.KE_GPU_CULL_MODE_NONE;
    pp.front_face = abi_render.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = (&fwd.vbl)[0..1];
    pp.blend_state.blend_enabled = true;
    pp.blend_state.src_color = abi_render.KE_GPU_BLEND_FACTOR_SRC_ALPHA;
    pp.blend_state.dst_color = abi_render.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = abi_render.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = abi_render.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = abi_render.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = abi_render.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = true;
    pp.depth_stencil.depth_write_enabled = false;
    pp.depth_stencil.depth_compare = abi_render.KE_GPU_COMPARE_LESS_EQUAL;
    try R.check(fwd.groups.place(&pp));
    pp.color_target_formats[0] = core.*.chain_format.?(core, abi_render.KE_RENDER_STAGE_TRANSPARENT);
    pp.color_target_count = 1;
    fwd.pipeline_template = pp;

    if (!fwd.resolvePipeline(DEFAULT_MATERIAL_SHADER)) {
        log.warn("transparent-forward: default material shader failed to load", .{});
        return error.NotInitialized;
    }
    if (core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template) == abi_render.KE_GPU_INVALID_HANDLE) {
        log.warn("transparent-forward: render pipeline creation failed", .{});
        return error.NotInitialized;
    }

    fwd.objects = .{ .device = dev, .binder = fwd.groups.binder, .layout = fwd.groups.layout, .buffer_label = "forward.obj_uniform", .set_label = "forward.obj_set" };
    try R.check(fwd.objects.?.ensure(1));

    fwd.opaque_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    rebuildFrameSet(fwd);

    var ac: u32 = 0;
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_COLOR), .access = abi_runtime.KE_ACCESS_WRITE };
    ac += 1;
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, abi_render.KE_RENDER_FRAME_DEPTH), .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = mesh_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = world_transform_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = camera_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = skybox_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = frame_cid, .access = abi_runtime.KE_ACCESS_READ };
    ac += 1;
    for ([_]?[:0]u8{ fwd.clusters, fwd.shadow }) |group| {
        const g = group orelse continue;
        fwd.access[ac] = .{ .cid = core.*.cid.?(core, g.ptr), .access = abi_runtime.KE_ACCESS_READ };
        ac += 1;
    }
    fwd.access_count = ac;

    const rd = abi_runtime.KE_ACCESS_READ;
    fwd.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = skybox_cid, .access = rd }, .{ .cid = mesh_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd } };
    fwd.queries = .{ .{ .terms = fwd.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = fwd.queries_terms[2..].ptr, .term_count = 1 }, .{ .terms = fwd.queries_terms[3..].ptr, .term_count = 2 } };
}

/// Gives the link back and releases the names, sets, buffers and layout the module holds, skipping
/// any still absent, so it also works after a partial `setup`. It does not free the module, and it
/// does not release the pipeline, which `setup` obtained from the render service.
fn destroyModule(fwd: *ForwardModule) void {
    if (fwd.io.chain != abi_render.KE_RENDER_CHAIN_NONE) fwd.core.*.leave_chain.?(fwd.core, fwd.io.chain);
    for ([_]?[:0]u8{ fwd.shadow, fwd.clusters }) |name| if (name) |n| gpa.free(n);
    if (fwd.frame_set != abi_render.KE_RENDER_BINDING_INVALID) fwd.groups.binder.destroy_set.?(fwd.groups.binder, fwd.frame_set);
    if (fwd.objects) |*objects| objects.release();
    fwd.draws.deinit(gpa);
    fwd.groups.release();
}

/// The `destroy` slot of the handle that `ke_render_forward_create` returns. It is the only place
/// that frees a module created successfully.
fn destroyHandle(self: ?*abi_render_forward_factory.ke_render_forward) callconv(.c) void {
    const fwd: *ForwardModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(fwd);
    gpa.destroy(fwd);
}

/// Factory declared in the plugin's forward_create.h. On success the returned handle's `ref` is the
/// module, and its `destroy` must be called to release it. On failure `ref` is null and the module
/// and its GPU objects are released. A missing runtime, service or device fails as an invalid
/// argument. A failure in `setup` or of the registration fails with its code.
export fn ke_render_forward_create(params_in: ?*const abi_render_forward_factory.ke_render_forward_params, out_forward: [*c]abi_render_forward_factory.ke_render_forward_handle) callconv(.c) abi_result.ke_result {
    const out = out_forward orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.service == null or p.device == null)
        return R.code(error.InvalidArgument);

    const fwd = gpa.create(ForwardModule) catch |err| return R.code(err);
    fwd.* = .{};
    setup(fwd, p) catch |err| {
        destroyModule(fwd);
        gpa.destroy(fwd);
        return R.code(err);
    };

    var params = std.mem.zeroes(abi_runtime.ke_runtime_system_params);
    params.name = "render.forward_transparent";
    params.phase = abi_runtime.KE_PHASE_RENDER;
    params.queries = &fwd.queries;
    params.query_count = fwd.queries.len;
    params.access_list = &fwd.access;
    params.access_count = fwd.access_count;
    params.pinned_thread = 0;
    params.user_data = fwd;
    params.execute = system;
    var system_id: abi_runtime.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(fwd);
        gpa.destroy(fwd);
        return registered;
    }

    out.* = .{ .ref = @ptrCast(fwd), .destroy = destroyHandle };
    return R.ok;
}

fn nameOf(name: ?[:0]u8) ?[*:0]const u8 {
    return if (name) |n| n.ptr else null;
}


const testing = std.testing;

fn blendUnlessZero(_: [*c]abi_render.ke_render_service, m: abi_render.ke_material_handle) callconv(.c) abi_render.ke_alpha_mode {
    return if (m.bits == 0) abi_render.KE_ALPHA_MODE_OPAQUE else abi_render.KE_ALPHA_MODE_BLEND;
}

fn blendingService() abi_render.ke_render_service {
    var svc = std.mem.zeroes(abi_render.ke_render_service);
    svc.material_alpha_mode = blendUnlessZero;
    return svc;
}

fn cameraSeeing(mask: u32) abi_render.ke_camera_component {
    var cam = std.mem.zeroes(abi_render.ke_camera_component);
    cam.cull_mask = mask;
    return cam;
}

fn meshOn(layers: u32) abi_render.ke_mesh_component {
    var m = std.mem.zeroes(abi_render.ke_mesh_component);
    m.layers = layers;
    m.material = .{ .bits = 7 };
    return m;
}

fn transformAt(z: f32) abi_spatial.ke_world_transform_component {
    var wt = std.mem.zeroes(abi_spatial.ke_world_transform_component);
    wt.matrix.m[14] = z;
    return wt;
}

var column_pool: [8][2]?*anyopaque = undefined;
var column_pool_next: usize = 0;

fn oneSegment(meshes: []const abi_render.ke_mesh_component, wts: []const abi_spatial.ke_world_transform_component) abi_ecs.ke_ecs_segment {
    var seg = std.mem.zeroes(abi_ecs.ke_ecs_segment);
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
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0b001), out[0].mesh.layers);
}

test "a camera whose mask names several layers draws a mesh on any one of them" {
    var svc = blendingService();
    const cam = cameraSeeing(0b101);
    const meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 2), n);
}

test "a mesh sharing one bit of a multi layer mask is drawn once, not once per bit" {
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render.ke_mesh_component{meshOn(0b111)};
    const wts = [_]abi_spatial.ke_world_transform_component{transformAt(-1)};
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 1), n);
}

test "a camera that names no layer draws nothing, even with meshes in front of it" {
    var svc = blendingService();
    const cam = cameraSeeing(0);
    const meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 0), n);
}

test "an opaque mesh the camera can see still stays out of the transparent pass" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    var opaque_mesh = meshOn(0b001);
    opaque_mesh.material = .{ .bits = 0 };
    const meshes = [_]abi_render.ke_mesh_component{ opaque_mesh, meshOn(0b001) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);
    const out = out_list.items;

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 7), out[0].mesh.material.bits);
}

test "the culled draws come back farthest first, so blending composites back to front" {
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-2), transformAt(-9), transformAt(-5) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

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
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]abi_spatial.ke_world_transform_component{ transformAt(2), transformAt(9), transformAt(5) };
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

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
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]abi_render.ke_mesh_component{meshOn(0b001)} ** 600;
    const wts = [_]abi_spatial.ke_world_transform_component{transformAt(-1)} ** 600;
    const segs = [_]abi_ecs.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 600), n);
}

test "meshes are gathered across every segment the query returned" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]abi_render.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]abi_spatial.ke_world_transform_component{transformAt(-1)};
    const b_meshes = [_]abi_render.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]abi_spatial.ke_world_transform_component{ transformAt(-2), transformAt(-3) };
    const segs = [_]abi_ecs.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out_list: std.ArrayList(Draw) = .empty;
    defer out_list.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, &out_list));
    const n: u32 = @intCast(out_list.items.len);

    try testing.expectEqual(@as(u32, 2), n);
}

const stubs = @import("stubs.zig");

test "creating and destroying the forward pass leaves no block allocated and no GPU resource live" {
    var dev: stubs.Device = undefined;
    dev.init();
    var core: stubs.Core = undefined;
    core.init(dev.api());
    var rt: stubs.Runtime = undefined;
    rt.init();
    var h: abi_render_forward_factory.ke_render_forward_handle = undefined;
    try R.check(ke_render_forward_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .ibl_enabled = false, .mesh_cid = 1, .world_transform_cid = 2, .camera_cid = 3, .skybox_cid = 4, .frame_cid = 5, .shadow = "shadow", .clusters = "clusters" }, &h));
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a forward pass whose shader fails to load releases what it had created" {
    var dev: stubs.Device = undefined;
    dev.init();
    var core: stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: stubs.Runtime = undefined;
    rt.init();
    var h: abi_render_forward_factory.ke_render_forward_handle = undefined;
    try testing.expect(ke_render_forward_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .ibl_enabled = false, .mesh_cid = 1, .world_transform_cid = 2, .camera_cid = 3, .skybox_cid = 4, .frame_cid = 5, .shadow = "shadow", .clusters = "clusters" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a forward pass the runtime refuses to register releases what it had created" {
    var dev: stubs.Device = undefined;
    dev.init();
    var core: stubs.Core = undefined;
    core.init(dev.api());
    var rt: stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var h: abi_render_forward_factory.ke_render_forward_handle = undefined;
    try testing.expect(ke_render_forward_create(&.{ .runtime = rt.api(), .service = core.api(), .device = dev.api(), .ibl_enabled = false, .mesh_cid = 1, .world_transform_cid = 2, .camera_cid = 3, .skybox_cid = 4, .frame_cid = 5, .shadow = "shadow", .clusters = "clusters" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
