//! The gbuffer pass: the render-phase system that rasterises the opaque meshes a camera sees into
//! the albedo, normal and emissive targets of the group it is given, which it declares on the
//! render service, and into the frame's depth. It also owns
//! the creation and teardown of that pass, behind the one factory it exports.

const abi_framework = @import("abi_framework");
const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_gbuffer").logFn };

const zm = @import("zmath");
const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_gbuffer_factory = @import("abi_render_gbuffer_factory");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const log = std.log.scoped(.render_gbuffer);

const heap = @import("heap");
const gpa = heap.gpa;

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

/// Called by `system` once the camera is known and before any draw is issued. It replaces the
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

/// The state of one gbuffer pass, allocated by `ke_render_gbuffer_create` and freed by
/// `destroyHandle`. Handles start as KE_GPU_INVALID_HANDLE and are filled by `setup`, which is what
/// lets `destroyModule` release a module whose setup stopped partway. `io` is handed to the render
/// service on every `begin_pass`, and its `writes` points into this module, so the module must not
/// move.
/// `destroyHandle` unregisters the system the factory registered before it frees the module.
const GBufferModule = struct {
    runtime: *abi_runtime.c.ke_runtime = undefined,
    system: abi_runtime.c.ke_system_id = 0,
    core: *abi_render.c.ke_render_service = undefined,
    device: *abi_render_gpu.c.ke_gpu_device = undefined,

    mesh_cid: abi_asset_resolver.c.ke_component_id = undefined,
    world_transform_cid: abi_asset_resolver.c.ke_component_id = undefined,
    camera_cid: abi_asset_resolver.c.ke_component_id = undefined,

    names: [3]?[:0]u8 = .{ null, null, null },

    pipeline_template: abi_render_gpu.c.ke_gpu_render_pipeline_params = undefined,
    attrs: [4]abi_render_gpu.c.ke_gpu_vertex_attribute = undefined,
    vbl: abi_render_gpu.c.ke_gpu_vertex_buffer_layout = undefined,
    groups: Groups = .{},
    frame_set: abi_asset_resolver.c.ke_render_resource_set = abi_render_gpu.c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    draws: std.ArrayList(Draw) = .empty,

    writes: [3][*c]const u8 = undefined,
    io: abi_render.c.ke_render_pass_io = undefined,
    access: [8]abi_runtime.c.ke_component_access = undefined,
    access_count: u32 = 0,
    queries_terms: [4]abi_runtime.c.ke_component_access = undefined,
    queries: [2]abi_runtime.c.ke_query_decl = undefined,

    /// Loads the vertex and fragment stages of the given material shader under this pass's name,
    /// and stores both in `pipeline_template` only when both loads succeed, so a false return
    /// leaves the template as it was. `setup` calls it for the default material and `system` for
    /// each draw.
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

/// Runs as the body of the system `ke_render_gbuffer_create` registers, receiving the module as its
/// user argument. Once it has begun a pass it always ends it, so a pass is recorded even when
/// nothing is drawn. It draws the meshes `collectDraws` selects: those on a layer the camera's cull
/// mask names, minus the blended ones. A draw writes its matrices into the next slot of the one
/// shared uniform buffer and binds that slot by dynamic offset; a draw whose geometry or shader is
/// missing is skipped without consuming a slot. It fails as out of memory when the draw list
/// cannot grow, and with the code of the call that failed when the per-draw uniforms cannot.
fn system(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const gb = moduleOf(user);
    const core = gb.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, &gb.io);
    if (pc == null) return R.ok;

    if (cam_segc == 0 or cam_segs.?[0].count == 0) {
        const rp0 = pc.?.begin_render.?(pc);
        rp0.?.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return R.ok;
    }

    const cam: *const abi_render_components.c.ke_camera_component = @ptrCast(@alignCast(cam_segs.?[0].columns.?[0]));
    const view_proj = zm.loadMat(core.*.frame_globals.?(core).?.view_proj[0..]);

    const rp = pc.?.begin_render.?(pc);
    gb.groups.binder.bind_render_set.?(gb.groups.binder, rp, gb.frame_set, null, 0);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    const objects = &gb.objects.?;
    if (!collectDraws(core, cam, segs.?, segc, &gb.draws)) {
        log.warn("gbuffer pass: draw list allocation failed", .{});
        rp.?.end.?(rp);
        core.*.end_pass.?(core, pc);
        return R.code(error.OutOfMemory);
    }
    const grown = objects.ensure(@intCast(gb.draws.items.len));
    if (grown != R.ok) {
        rp.?.end.?(rp);
        core.*.end_pass.?(core, pc);
        return grown;
    }

    var draw_idx: u32 = 0;
    for (gb.draws.items) |draw| {

        var vbo: abi_asset_resolver.c.ke_gpu_buffer = 0;
        var ibo: abi_asset_resolver.c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (!core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count)) continue;

        const model = zm.loadMat(draw.world.matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        const offset: u32 = Objects.offset(draw_idx);
        core.*.upload.?(core, objects.buffer, offset, &u, @sizeOf(PerObject));

        if (!gb.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;
        rp.?.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &gb.pipeline_template));

        gb.groups.bindMaterial(rp, core.*.material_binding.?(core, draw.mesh.material));
        objects.bind(rp, draw_idx);
        rp.?.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.?.set_index_buffer.?(rp, ibo, abi_render_gpu.c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.?.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
        draw_idx += 1;
    }
    rp.?.end.?(rp);
    core.*.end_pass.?(core, pc);
    return R.ok;
}

/// Called once by `ke_render_gbuffer_create`. It creates the GPU objects and fills
/// `pipeline_template`, `io`, `access` and `queries`, and it requests the pipeline now, so a
/// failure there fails creation instead of the first frame. On failure the module keeps the
/// handles it made for `destroyModule`.
fn setup(gb: *GBufferModule, p: *const abi_render_gbuffer_factory.c.ke_render_gbuffer_params) R.Error!void {
    const core: *abi_render.c.ke_render_service = p.service.?;
    const dev: *abi_render_gpu.c.ke_gpu_device = p.device.?;
    const mesh_cid = p.scene.?.component_ids.?(p.scene).?.mesh;
    const world_transform_cid = p.scene.?.component_ids.?(p.scene).?.world_transform;
    const camera_cid = p.scene.?.component_ids.?(p.scene).?.camera;
    const frame_cid = p.frame.?.frame_cid.?(p.frame);
    gb.core = core;
    gb.device = dev;
    gb.mesh_cid = mesh_cid;
    gb.world_transform_cid = world_transform_cid;
    gb.camera_cid = camera_cid;

    const group = std.mem.span(p.output.?);
    const suffixes = [3][]const u8{ abi_render_contract.c.KE_RENDER_GBUFFER_ALBEDO, abi_render_contract.c.KE_RENDER_GBUFFER_NORMAL, abi_render_contract.c.KE_RENDER_GBUFFER_EMISSIVE };
    for (suffixes, &gb.names) |suffix, *name| {
        name.* = std.fmt.allocPrintSentinel(gpa, "{s}{s}", .{ group, suffix }, 0) catch return error.OutOfMemory;
    }

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

    var pp = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
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
    pp.color_target_formats[0] = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    pp.color_target_formats[1] = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    pp.color_target_formats[2] = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
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

    const formats = [3]abi_render_gpu.c.ke_gpu_texture_format{ abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT };
    var cids: [3]abi_asset_resolver.c.ke_component_id = undefined;
    for (gb.names, formats, &cids, 0..) |name, format, *cid, i| {
        try R.check(core.*.declare.?(core, &abi_render.c.ke_render_resource_params{
            .name = name.?.ptr,
            .type = abi_render.c.KE_RENDER_RESOURCE_TEXTURE,
            .format = format,
            .size_mode = abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
            .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
        }, cid));
        gb.writes[i] = name.?.ptr;
    }

    gb.io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    gb.io.name = "render.gbuffer";
    gb.io.writes = @ptrCast(&gb.writes);
    gb.io.writes_count = 3;
    gb.io.depth = abi_render.c.KE_RENDER_DEPTH_WRITE;

    gb.access = .{
        .{ .cid = cids[0], .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = cids[1], .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = cids[2], .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = core.*.cid.?(core, abi_render.c.KE_RENDER_FRAME_DEPTH), .access = abi_runtime.c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = abi_runtime.c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = abi_runtime.c.KE_ACCESS_READ },
    };
    gb.access_count = 8;

    const rd = abi_runtime.c.KE_ACCESS_READ;
    gb.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = mesh_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd } };
    gb.queries = .{ .{ .terms = gb.queries_terms[0..].ptr, .term_count = 2 }, .{ .terms = gb.queries_terms[2..].ptr, .term_count = 2 } };
}

/// Releases the GPU objects and sets `setup` created, skipping any still invalid, so it also serves a module whose setup stopped partway. Used on creation failure and by
/// `destroyHandle`.
fn destroyModule(gb: *GBufferModule) void {
    for (gb.names) |name| if (name) |n| gpa.free(n);
    if (gb.objects) |*objects| objects.release();
    gb.draws.deinit(gpa);
    if (gb.frame_set != abi_render_gpu.c.KE_RENDER_BINDING_INVALID) gb.groups.binder.destroy_set.?(gb.groups.binder, gb.frame_set);
    gb.groups.release();
}

/// The destroy slot of the handle `ke_render_gbuffer_create` returns: releases the module's GPU
/// objects and frees the module. A null ref does nothing.
fn destroyHandle(self: ?*abi_render_gbuffer_factory.c.ke_render_gbuffer) callconv(.c) void {
    const gb: *GBufferModule = @ptrCast(@alignCast(self orelse return));
    _ = gb.runtime.unregister_system.?(gb.runtime, gb.system);
    destroyModule(gb);
    gpa.destroy(gb);
}

/// The factory the plugin exports, declared in the plugin's factory header. On success it returns
/// the module as the handle's ref and `destroyHandle` as its destroy slot. A missing runtime,
/// render service, device or output fails as an invalid argument and a failed allocation as
/// out of memory. A failing setup, or a runtime that refuses the registration, fails with its code
/// and leaves the handle zeroed after releasing the module.
export fn ke_render_gbuffer_create(params_in: ?*const abi_render_gbuffer_factory.c.ke_render_gbuffer_params, out_gbuffer: [*c]abi_render_gbuffer_factory.c.ke_render_gbuffer_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_gbuffer orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const p = params_in orelse return R.code(error.InvalidArgument);
    const rt: *abi_runtime.c.ke_runtime = p.runtime orelse return R.code(error.InvalidArgument);
    if (p.scene == null or p.frame == null or p.service == null or p.device == null or p.output == null) return R.code(error.InvalidArgument);

    const gb = gpa.create(GBufferModule) catch |err| return R.code(err);
    gb.* = .{};
    setup(gb, p) catch |err| {
        destroyModule(gb);
        gpa.destroy(gb);
        return R.code(err);
    };

    var params = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    params.name = "render.gbuffer";
    params.phase = abi_runtime.c.KE_PHASE_RENDER;
    params.queries = &gb.queries;
    params.query_count = gb.queries.len;
    params.access_list = &gb.access;
    params.access_count = gb.access_count;
    params.user_data = gb;
    params.execute = system;
    var system_id: abi_runtime.c.ke_system_id = 0;
    const registered = rt.register_system.?(rt, &params, &system_id);
    if (registered != R.ok) {
        destroyModule(gb);
        gpa.destroy(gb);
        return registered;
    }
    gb.runtime = rt;
    gb.system = system_id;

    out.* = .{ .ref = @ptrCast(gb), .destroy = destroyHandle };
    return R.ok;
}


const testing = std.testing;

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .mesh = 1, .camera = 2, .directional_light = 3, .point_light = 4, .spot_light = 5, .ambient_light = 6, .skybox = 7, .sprite2d = 8, .label = 9, .world_transform = 10 });

fn testComponentIds(_: [*c]abi_render.c.ke_render_scene_resolve) callconv(.c) [*c]const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds };

fn testFrameCid(_: [*c]abi_render.c.ke_render_frame) callconv(.c) abi_render.c.ke_component_id {
    return 11;
}

var test_frame: abi_render.c.ke_render_frame = .{ .handle = null, .frame_cid = testFrameCid };


fn opaqueUnlessZero(_: [*c]abi_render.c.ke_render_service, m: abi_render_handles.c.ke_material_handle) callconv(.c) abi_render_handles.c.ke_alpha_mode {
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

const Rig = struct {
    dev: zsub.For(abi_render_gpu.c.ke_gpu_device),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    core: zsub.For(abi_render.c.ke_render_service),
    rt: zsub.For(abi_runtime.c.ke_runtime),

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
        _ = self.core.when(.cid).returnsFresh();
        _ = self.core.when(.declare).writesFresh(2);
        _ = self.core.when(.texture_view).returnsFresh();
        try self.rt.init();
        _ = self.rt.when(.register_system).writesFresh(2);
    }

    fn deinit(self: *Rig) void {
        self.rt.deinit();
        self.core.deinit();
        self.binder.deinit();
        self.dev.deinit();
    }

    fn expectReleased(self: *Rig) !void {
        try self.dev.received(.destroy_buffer).where(zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE)).sameAs(self.dev.received(.create_buffer));
        try self.binder.received(.destroy_shader_layout).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID)).sameAs(self.binder.received(.create_set));
    }
};

test "creating and destroying the gbuffer pass leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try R.check(ke_render_gbuffer_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h));
    h.destroy.?(h.ref);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "destroying the gbuffer pass unregisters every system it registered" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try R.check(ke_render_gbuffer_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h));
    h.destroy.?(h.ref);
    try rig.rt.received(.register_system).atLeast(1);
    try rig.rt.received(.unregister_system).where(zsub.argIs(1, @as(abi_runtime.c.ke_system_id, 0))).never();
    try rig.rt.received(.unregister_system).sameAs(rig.rt.received(.register_system));
}

test "a gbuffer pass whose shader fails to load releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.core.when(.load_shader).returns(abi_result.c.KE_RESULT_GENERAL);
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try testing.expect(ke_render_gbuffer_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}

test "a missing frame is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_gbuffer_create(&.{ .scene = &test_scene, .frame = null, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h)));
}

test "a missing scene is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_gbuffer_create(&.{ .scene = null, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h)));
}

test "a gbuffer pass the runtime refuses to register releases what it had created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.rt.when(.register_system).returns(abi_result.c.KE_RESULT_OUT_OF_MEMORY);
    var h: abi_render_gbuffer_factory.c.ke_render_gbuffer_handle = undefined;
    try testing.expect(ke_render_gbuffer_create(&.{ .scene = &test_scene, .frame = &test_frame, .runtime = rig.rt.api(), .service = rig.core.api(), .device = rig.dev.api(), .output = "gbuffer" }, &h) != R.ok);
    try testing.expect(h.ref == null);
    try rig.expectReleased();
    try heap.expectNoLeaks();
}
