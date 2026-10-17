//! The gbuffer pass: the render-phase system that rasterises the opaque meshes a camera sees into
//! the albedo, normal, emissive and depth targets it declares on the render service. It also owns
//! the creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;

/// The suffix `resolvePipeline` appends to a material shader name to pick this pass's variant.
const Groups = @import("material_pass_groups").MaterialPassGroups(c);
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
    mesh: *const c.ke_mesh_component,
    world: *const c.ke_world_transform_component,
};

const Objects = @import("object_uniforms").ObjectUniforms(c, PerObject);

/// Called by `system` once the camera is known and before any draw is issued. It replaces the
/// contents of `out` with every draw of the body, and returns false when the list cannot grow.
fn collectDraws(
    core: *c.ke_render_service,
    cam: *const c.ke_camera_component,
    segs: [*]const c.ke_ecs_segment,
    seg_count: usize,
    out: *std.ArrayList(Draw),
) bool {
    out.clearRetainingCapacity();
    var s: usize = 0;
    while (s < seg_count) : (s += 1) {
        const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const wts: [*c]const c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            if (meshes[i].layers & cam.cull_mask == 0) continue;
            if (core.material_alpha_mode.?(core, meshes[i].material) == c.KE_ALPHA_MODE_BLEND) continue;
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
const GBufferModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,

    mesh_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,

    pipeline_template: c.ke_gpu_render_pipeline_params = undefined,
    attrs: [4]c.ke_gpu_vertex_attribute = undefined,
    vbl: c.ke_gpu_vertex_buffer_layout = undefined,
    groups: Groups = .{},
    frame_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,
    draws: std.ArrayList(Draw) = .empty,

    writes: [4][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [8]c.ke_component_access = undefined,
    access_count: u32 = 0,
    queries_terms: [4]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,

    /// Loads the vertex and fragment stages of the given material shader under this pass's name,
    /// and stores both in `pipeline_template` only when both loads succeed, so a false return
    /// leaves the template as it was. `setup` calls it for the default material and `system` for
    /// each draw.
    fn resolvePipeline(gb: *GBufferModule, shader: [*c]const u8) bool {
        var name_buf: [rc_MAX_SHADER_QUALIFIED]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "{s}.{s}", .{ std.mem.span(shader), PASS_NAME }) catch return false;
        const vs = gb.core.*.load_shader.?(gb.core, name.ptr, c.KE_GPU_SHADER_STAGE_VERTEX, null);
        if (vs == c.KE_GPU_INVALID_HANDLE) return false;
        const fs = gb.core.*.load_shader.?(gb.core, name.ptr, c.KE_GPU_SHADER_STAGE_FRAGMENT, null);
        if (fs == c.KE_GPU_INVALID_HANDLE) return false;
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
/// missing is skipped without consuming a slot.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const gb = moduleOf(user);
    const core = gb.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, &gb.io);
    if (pc == null) return true;

    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return true;
    }

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const view_proj = zm.loadMat(core.*.frame_globals.?(core).*.view_proj[0..]);

    const rp = pc.*.begin_render.?(pc);
    gb.groups.binder.bind_render_set.?(gb.groups.binder, rp, gb.frame_set, null, 0);

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    const objects = &gb.objects.?;
    if (!collectDraws(core, cam, segs, segc, &gb.draws)) {
        c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "gbuffer pass: draw list allocation failed", @src().file, @intCast(@src().line), null);
        rp.*.end.?(rp);
        core.*.end_pass.?(core, pc);
        return false;
    }
    if (!objects.ensure(@intCast(gb.draws.items.len), out_error)) {
        rp.*.end.?(rp);
        core.*.end_pass.?(core, pc);
        return false;
    }

    var draw_idx: u32 = 0;
    for (gb.draws.items) |draw| {

        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
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
        rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &gb.pipeline_template));

        gb.groups.bindMaterial(rp, core.*.material_binding.?(core, draw.mesh.material));
        objects.bind(rp, draw_idx);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
        draw_idx += 1;
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Called once by `ke_render_gbuffer_create`. It creates the GPU objects and fills
/// `pipeline_template`, `io`, `access` and `queries`, and it requests the pipeline now, so a
/// failure there fails creation instead of the first frame. On failure it returns false with the
/// error written to the error output, and the module keeps the handles it made for `destroyModule`.
fn setup(gb: *GBufferModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
         camera_cid: c.ke_component_id, frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    gb.core = core;
    gb.device = dev;
    gb.mesh_cid = mesh_cid;
    gb.world_transform_cid = world_transform_cid;
    gb.camera_cid = camera_cid;

    const binder: *c.ke_render_resource_binder = core.*.resource_binder.?(core);
    if (!gb.groups.init(binder, DEFAULT_MATERIAL_SHADER ++ "." ++ PASS_NAME, out_error)) return false;
    gb.frame_set = binder.create_set.?(binder, gb.groups.layout, null, "gbuffer.frame_set", null, 0, out_error);
    if (gb.frame_set == c.KE_RENDER_BINDING_INVALID) return false;

    gb.attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    gb.vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &gb.attrs,
    };

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.label = "gbuffer.pipeline";
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &gb.vbl;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = true;
    pp.depth_stencil.depth_write_enabled = true;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    if (!gb.groups.place(&pp, out_error)) return false;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    pp.color_target_formats[1] = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    pp.color_target_formats[2] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    pp.color_target_count = 3;
    gb.pipeline_template = pp;

    if (!gb.resolvePipeline(DEFAULT_MATERIAL_SHADER)) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "gbuffer pass: default material shader failed to load", @src().file, @intCast(@src().line), null);
        return false;
    }
    if (core.*.get_or_create_pipeline.?(core, &gb.pipeline_template) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "gbuffer pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    gb.objects = .{ .device = dev, .binder = binder, .layout = gb.groups.layout, .buffer_label = "gbuffer.obj_uniform", .set_label = "gbuffer.obj_set" };
    if (!gb.objects.?.ensure(1, out_error)) return false;

    const albedo_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "gbuffer_albedo",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const normal_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "gbuffer_normal",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const emissive_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "gbuffer_emissive",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const depth_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);

    gb.writes = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth" };
    gb.io = std.mem.zeroes(c.ke_render_pass_io);
    gb.io.name = "render.gbuffer";
    gb.io.writes = @ptrCast(&gb.writes);
    gb.io.writes_count = 4;

    gb.access = .{
        .{ .cid = albedo_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = normal_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = emissive_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };
    gb.access_count = 8;

    const rd = c.KE_ACCESS_READ;
    gb.queries_terms = .{ .{ .cid = camera_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd }, .{ .cid = mesh_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd } };
    gb.queries = .{ .{ .terms = &gb.queries_terms[0], .term_count = 2 }, .{ .terms = &gb.queries_terms[2], .term_count = 2 } };
    return true;
}

/// Releases the GPU objects and sets `setup` created, skipping any still invalid, so it also serves a module whose setup stopped partway. Used on creation failure and by
/// `destroyHandle`.
fn destroyModule(gb: *GBufferModule) void {
    if (gb.objects) |*objects| objects.release();
    gb.draws.deinit(gpa);
    if (gb.frame_set != c.KE_RENDER_BINDING_INVALID) gb.groups.binder.destroy_set.?(gb.groups.binder, gb.frame_set);
    gb.groups.release();
}

/// The destroy slot of the handle `ke_render_gbuffer_create` returns: releases the module's GPU
/// objects and frees the module. A null ref does nothing.
fn destroyHandle(self: ?*c.ke_render_gbuffer) callconv(.c) void {
    const gb: *GBufferModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(gb);
    gpa.destroy(gb);
}

/// The factory the plugin exports, declared in the plugin's factory header. On success it returns
/// the module as the handle's ref and `destroyHandle` as its destroy slot. A null runtime, render
/// service, device or camera, or a failed allocation, returns the empty handle without writing the
/// error output. A failing setup, or a runtime that refuses the registration, writes the error and
/// returns the empty handle after releasing the module.
export fn ke_render_gbuffer_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                    device: ?*c.ke_gpu_device,
                                    mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                    camera_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_gbuffer_handle {
    const empty = c.ke_render_gbuffer_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const gb = gpa.create(GBufferModule) catch return empty;
    gb.* = .{};
    if (!setup(gb, dev, core_ref, mesh_cid, world_transform_cid, camera_cid, frame_cid, out_error)) {
        destroyModule(gb);
        gpa.destroy(gb);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.gbuffer";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &gb.queries;
    params.query_count = gb.queries.len;
    params.access_list = &gb.access;
    params.access_count = gb.access_count;
    params.pinned_thread = 0;
    params.user_data = gb;
    params.execute = system;
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(gb);
        gpa.destroy(gb);
        return empty;
    }

    return .{ .ref = @ptrCast(gb), .destroy = destroyHandle };
}

const testing = std.testing;

fn opaqueUnlessZero(_: [*c]c.ke_render_service, m: c.ke_material_handle) callconv(.c) c.ke_alpha_mode {
    return if (m.bits == 0) c.KE_ALPHA_MODE_BLEND else c.KE_ALPHA_MODE_OPAQUE;
}

fn opaqueService() c.ke_render_service {
    var svc = std.mem.zeroes(c.ke_render_service);
    svc.material_alpha_mode = opaqueUnlessZero;
    return svc;
}

fn cameraSeeing(mask: u32) c.ke_camera_component {
    var cam = std.mem.zeroes(c.ke_camera_component);
    cam.cull_mask = mask;
    return cam;
}

fn meshOn(layers: u32) c.ke_mesh_component {
    var m = std.mem.zeroes(c.ke_mesh_component);
    m.layers = layers;
    m.material = .{ .bits = 7 };
    return m;
}

var column_pool: [8][2]?*anyopaque = undefined;
var column_pool_next: usize = 0;

fn oneSegment(meshes: []const c.ke_mesh_component, wts: []const c.ke_world_transform_component) c.ke_ecs_segment {
    var seg = std.mem.zeroes(c.ke_ecs_segment);
    const cols = &column_pool[column_pool_next % column_pool.len];
    column_pool_next += 1;
    cols[0] = @constCast(@ptrCast(meshes.ptr));
    cols[1] = @constCast(@ptrCast(wts.ptr));
    seg.columns = &cols[0];
    seg.column_count = 2;
    seg.count = meshes.len;
    return seg;
}

test "a mesh on a layer the camera's cull_mask omits is not drawn" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b010);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 3;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));

    try testing.expectEqual(@as(usize, 1), out.items.len);
    try testing.expectEqual(@as(u32, 0b010), out.items[0].mesh.layers);
}

test "a camera that names no layer draws nothing into the gbuffer" {
    var svc = opaqueService();
    const cam = cameraSeeing(0);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 0), out.items.len);
}

test "a blending mesh the camera can see is left to the forward pass" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    var blended = meshOn(0b001);
    blended.material = .{ .bits = 0 };
    const meshes = [_]c.ke_mesh_component{ blended, meshOn(0b001) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));

    try testing.expectEqual(@as(usize, 1), out.items.len);
    try testing.expectEqual(@as(u32, 7), out.items[0].mesh.material.bits);
}

test "every visible mesh is collected, however many there are" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]c.ke_mesh_component{meshOn(0b001)} ** 600;
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 600;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 600), out.items.len);
}

test "meshes are gathered across every segment the query returned" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]c.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)};
    const b_meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out: std.ArrayList(Draw) = .empty;
    defer out.deinit(gpa);
    try testing.expect(collectDraws(&svc, &cam, &segs, segs.len, &out));
    try testing.expectEqual(@as(usize, 2), out.items.len);
}

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the gbuffer pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_gbuffer_create(rt.api(), core.api(), dev.api(), 1, 2, 3, 4, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a gbuffer pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    const h = ke_render_gbuffer_create(rt.api(), core.api(), dev.api(), 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a gbuffer pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    const h = ke_render_gbuffer_create(rt.api(), core.api(), dev.api(), 1, 2, 3, 4, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
