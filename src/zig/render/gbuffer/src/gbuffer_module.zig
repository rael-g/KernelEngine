const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

const PASS_NAME = "gbuffer";
const DEFAULT_MATERIAL_SHADER = "standard";

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256;

const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

const Draw = struct {
    mesh: *const c.ke_mesh_component,
    world: *const c.ke_world_transform_component,
};

/// The meshes this camera owes the opaque pass: those whose layers the cull_mask
/// names and whose material does not blend. Returns how many of `out` were filled.
fn collectDraws(
    core: *c.ke_render_service,
    cam: *const c.ke_camera_component,
    segs: [*]const c.ke_ecs_segment,
    seg_count: usize,
    out: []Draw,
) u32 {
    var count: u32 = 0;
    var s: usize = 0;
    while (s < seg_count and count < out.len) : (s += 1) {
        const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const wts: [*c]const c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count and count < out.len) : (i += 1) {
            if (meshes[i].layers & cam.cull_mask == 0) continue;
            if (core.material_alpha_mode.?(core, meshes[i].material) == c.KE_ALPHA_MODE_BLEND) continue;
            out[count] = .{ .mesh = @ptrCast(&meshes[i]), .world = @ptrCast(&wts[i]) };
            count += 1;
        }
    }
    return count;
}

const GBufferModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,

    mesh_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,

    pipeline_template: c.ke_gpu_render_pipeline_params = undefined,
    attrs: [4]c.ke_gpu_vertex_attribute = undefined,
    vbl: c.ke_gpu_vertex_buffer_layout = undefined,
    empty_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    empty_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [4][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [8]c.ke_component_access = undefined,
    access_count: u32 = 0,
    queries: [2]c.ke_query_decl = undefined,

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

const rc_MAX_SHADER_QUALIFIED = 128;

/// View matrix from where the camera ended up in world space. A camera whose
/// basis carries no rotation at all is aimed at the origin instead: an authored
/// camera that only set a position would otherwise stare down -Z at nothing.
fn cameraView(cam_wt: *const c.ke_world_transform_component) zm.Mat {
    const m = cam_wt.matrix.m;
    const eye = zm.f32x4(m[12], m[13], m[14], 1.0);
    const unrotated = @abs(m[1]) < 1e-6 and @abs(m[2]) < 1e-6 and @abs(m[4]) < 1e-6 and
        @abs(m[6]) < 1e-6 and @abs(m[8]) < 1e-6 and @abs(m[9]) < 1e-6;
    if (unrotated) return zm.lookAtRh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0));
    const fwd = zm.f32x4(-m[8], -m[9], -m[10], 0);
    const up = zm.f32x4(m[4], m[5], m[6], 0);
    return zm.lookToRh(eye, fwd, up);
}

fn makeProjection(ndc: c.ke_ndc_convention, cam: *const c.ke_camera_component, aspect: f32) zm.Mat {
    var p = if (cam.orthographic != 0) ortho: {
        const h = cam.orthographic_size * 2.0;
        const w = h * aspect;
        break :ortho if (ndc.z_zero_to_one != 0)
            zm.orthographicRh(w, h, cam.near_plane, cam.far_plane)
        else
            zm.orthographicRhGl(w, h, cam.near_plane, cam.far_plane);
    } else persp: {
        const fovy = cam.fov * @as(f32, std.math.pi / 180.0);
        break :persp if (ndc.z_zero_to_one != 0)
            zm.perspectiveFovRh(fovy, aspect, cam.near_plane, cam.far_plane)
        else
            zm.perspectiveFovRhGl(fovy, aspect, cam.near_plane, cam.far_plane);
    };
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

inline fn moduleOf(user: ?*anyopaque) *GBufferModule {
    return @alignCast(@ptrCast(user.?));
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const gb = moduleOf(user);
    const core = gb.core;

    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, ctx, &gb.io);
    if (pc == null) return;

    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    }

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const view = cameraView(cam_wt);
    const proj = makeProjection(gb.ndc, cam, aspect);
    const view_proj = zm.mul(view, proj);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_bind_group.?(rp, 0, gb.empty_bg, null, 0);

    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 1, &segc);
    var selected: [MAX_DRAWS]Draw = undefined;
    const selected_count = collectDraws(core, cam, segs, segc, selected[0..]);

    var draw_idx: u32 = 0;
    var d: u32 = 0;
    while (d < selected_count) : (d += 1) {
        const draw = selected[d];

        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count) == 0) continue;

        const model = zm.loadMat(draw.world.matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        const offset: u32 = draw_idx * UNIFORM_STRIDE;
        core.*.upload.?(core, gb.obj_uniform, offset, &u, @sizeOf(PerObject));

        if (!gb.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;
        rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &gb.pipeline_template));

        const mat_bg = core.*.material_bind_group.?(core, draw.mesh.material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0);
        rp.*.set_bind_group.?(rp, 2, gb.obj_bind_group, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
        draw_idx += 1;
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(gb: *GBufferModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         ndc: c.ke_ndc_convention, mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
         camera_cid: c.ke_component_id, frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    gb.core = core;
    gb.device = dev;
    gb.ndc = ndc;
    gb.mesh_cid = mesh_cid;
    gb.world_transform_cid = world_transform_cid;
    gb.camera_cid = camera_cid;

    gb.empty_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 0,
        .entries = null,
    });
    gb.empty_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = gb.empty_bgl,
        .entry_count = 0,
        .entries = null,
    }, out_error);
    if (gb.empty_bg == c.KE_GPU_INVALID_HANDLE) return false;

    const obj_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0,
        .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 1,
        .view_dimension = 0,
    };
    const obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &obj_bgl_entry,
    });

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
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &gb.vbl;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 1;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    pp.bind_group_layouts[0] = gb.empty_bgl;
    pp.bind_group_layouts[1] = core.*.material_layout.?(core);
    pp.bind_group_layouts[2] = obj_bgl;
    pp.bind_group_layout_count = 3;
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

    gb.obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (gb.obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = gb.obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    gb.obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    }, out_error);
    if (gb.obj_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    const albedo_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "gbuffer_albedo",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const normal_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "gbuffer_normal",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const emissive_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "gbuffer_emissive",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);
    const depth_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);

    gb.writes = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth" };
    gb.io = std.mem.zeroes(c.ke_render_pass_io);
    gb.io.writes = @ptrCast(&gb.writes);
    gb.io.writes_count = 4;
    gb.io.cmd_slot = 3;

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
    gb.queries = std.mem.zeroes([2]c.ke_query_decl);
    gb.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    gb.queries[0].terms[1] = .{ .cid = world_transform_cid, .access = rd };
    gb.queries[0].term_count = 2;
    gb.queries[1].terms[0] = .{ .cid = mesh_cid, .access = rd };
    gb.queries[1].terms[1] = .{ .cid = world_transform_cid, .access = rd };
    gb.queries[1].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_gbuffer) callconv(.c) void {
    const gb: *GBufferModule = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(gb);
}

export fn ke_render_gbuffer_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                    device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                    mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                    camera_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_gbuffer_handle {
    const empty = c.ke_render_gbuffer_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const gb = gpa.create(GBufferModule) catch return empty;
    gb.* = .{};
    if (!setup(gb, dev, core_ref, ndc, mesh_cid, world_transform_cid, camera_cid, frame_cid, out_error)) {
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
    _ = rt.register_system.?(rt, &params, null);

    return .{ .ref = @ptrCast(gb), .destroy = destroyHandle };
}

const testing = std.testing;

/// Reports every material as opaque except handle 0.
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

fn oneSegment(meshes: []const c.ke_mesh_component, wts: []const c.ke_world_transform_component) c.ke_ecs_segment {
    var seg = std.mem.zeroes(c.ke_ecs_segment);
    seg.columns[0] = @constCast(@ptrCast(meshes.ptr));
    seg.columns[1] = @constCast(@ptrCast(wts.ptr));
    seg.count = meshes.len;
    return seg;
}

test "a mesh on a layer the camera's cull_mask omits is not drawn" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b010);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 3;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0b010), out[0].mesh.layers);
}

test "a camera that names no layer draws nothing into the gbuffer" {
    var svc = opaqueService();
    const cam = cameraSeeing(0);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    try testing.expectEqual(@as(u32, 0), collectDraws(&svc, &cam, &segs, segs.len, out[0..]));
}

test "a blending mesh the camera can see is left to the forward pass" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    var blended = meshOn(0b001);
    blended.material = .{ .bits = 0 };
    const meshes = [_]c.ke_mesh_component{ blended, meshOn(0b001) };
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 7), out[0].mesh.material.bits);
}

test "collection stops at the caller's capacity instead of writing past it" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]c.ke_mesh_component{meshOn(0b001)} ** 3;
    const wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 3;
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [2]Draw = undefined;
    try testing.expectEqual(@as(u32, 2), collectDraws(&svc, &cam, &segs, segs.len, out[0..]));
}

test "meshes are gathered across every segment the query returned" {
    var svc = opaqueService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]c.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)};
    const b_meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]c.ke_world_transform_component{std.mem.zeroes(c.ke_world_transform_component)} ** 2;
    const segs = [_]c.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out: [8]Draw = undefined;
    try testing.expectEqual(@as(u32, 2), collectDraws(&svc, &cam, &segs, segs.len, out[0..]));
}
