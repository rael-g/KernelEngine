const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

// Shadow-depth pass, extracted as the §9.8 decomposition pilot: this file owns
// every shadow-specific GPU resource, its own runtime system, and the cids it
// needs, taking them as setup parameters rather than reaching into the parent
// module's state directly — render_module.zig only holds one `ShadowModule`
// field and forwards the cross-cutting ids (mesh/transform/light/frame) once,
// at setup. When shadow_enabled is false, `setup` still allocates the tiny
// lvp_uniform (read unconditionally by the single forward shader as its
// neutral-default hook resource — see forward_lit.slang) but none of the
// expensive resources (shadow_map/shadow_depth render targets, pipeline,
// per-draw buffers, the "render.shadow" system) exist.

const shadow_vs_wgsl = @embedFile("shadow.vs.wgsl");
const shadow_fs_wgsl = @embedFile("shadow.fs.wgsl");

const SHADOW_RES = 1024; // shadow map resolution

// Duplicated from render_module.zig rather than shared, matching the
// decoupling precedent already established in cluster_feature.slang (its own
// header comment: "Duplicated rather than shared via import to keep this
// feature decoupled from the pass file").
const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Per-object model for the shadow pass (set 1).
const ShadowObj = extern struct { model: [16]f32 };

// Mirrors ke_directional_light_component (10 floats, see render/components.h).
const DirLight = extern struct {
    dir: [3]f32,
    rgb: [3]f32,
    intensity: f32,
    ambient: [3]f32,
};

pub const ShadowModule = struct {
    enabled: bool = false,

    // Borrowed cross-cutting refs, captured once at setup so the system body
    // never reaches into the parent ModuleState.
    core: c.ke_render_core_handle = undefined,
    ndc: c.ke_ndc_convention = undefined,
    mesh_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    view: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE, // the shadow map's view — read by the forward's set-0 binding 3/5
    pipeline: c.ke_gpu_pipeline = c.KE_GPU_INVALID_HANDLE,
    lvp_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE, // set 0 (this pass) AND read by the forward's binding 4
    lvp_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [2][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [6]c.ke_component_access = undefined,
};

// Orthographic light view-proj; the light source sits opposite the travel
// direction. Matches the legacy bgfx ShadowRenderSystem (frustum 20, far 50).
fn lightViewProj(ndc: c.ke_ndc_convention, ldir_in: zm.Vec) zm.Mat {
    const ldir = zm.normalize3(ldir_in);
    const eye3 = ldir * zm.f32x4s(-25.0);
    const eye = zm.f32x4(eye3[0], eye3[1], eye3[2], 1.0);
    const up = if (@abs(ldir[1]) > 0.99) zm.f32x4(0, 0, 1, 0) else zm.f32x4(0, 1, 0, 0);
    const lview = zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), up);
    const lproj = makeOrtho(ndc, 20.0, 20.0, 0.1, 50.0);
    return zm.mul(lview, lproj);
}

fn makeOrtho(ndc: c.ke_ndc_convention, w: f32, h: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.orthographicLh(w, h, near, far)
    else
        zm.orthographicLhGl(w, h, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

fn lightDirOf(ctx: ?*c.ke_system_ctx, light_cid: c.ke_component_id) zm.Vec {
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, light_cid, &ents, &data, &count);
    if (count == 0) return zm.f32x4(-0.4, -1.0, -0.3, 0.0);
    const dl: *const DirLight = @ptrCast(@alignCast(data));
    return zm.f32x4(dl.dir[0], dl.dir[1], dl.dir[2], 0.0);
}

inline fn moduleOf(user: ?*anyopaque) *ShadowModule {
    return @alignCast(@ptrCast(user.?));
}

pub fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const sh = moduleOf(user);
    const core = sh.core.ref;

    const lvp = lightViewProj(sh.ndc, lightDirOf(ctx, sh.light_cid));
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    core.*.upload.?(core, sh.lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, ctx, &sh.io);
    if (pc == null) return;

    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, sh.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, sh.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        var u: ShadowObj = undefined;
        @memcpy(u.model[0..], tc.world_matrix.m[0..16]);
        core.*.upload.?(core, sh.obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(ShadowObj));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, sh.pipeline);
    rp.*.set_bind_group.?(rp, 0, sh.lvp_bg, null, 0);
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        rp.*.set_bind_group.?(rp, 1, sh.obj_bg, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Allocates lvp_uniform unconditionally (tiny, 64 bytes — the forward shader's
// neutral-default hook resource, see forward_lit.slang) and, only when
// `enabled`, the expensive resources: the shadow_map/shadow_depth render
// targets, the shadow pipeline, and the per-draw uniform ring.
pub fn setup(sh: *ShadowModule, dev: *c.ke_gpu_device, core: c.ke_render_core_handle,
             ndc: c.ke_ndc_convention, enabled: bool, mesh_cid: c.ke_component_id,
             transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
             frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    sh.enabled = enabled;
    sh.core = core;
    sh.ndc = ndc;
    sh.mesh_cid = mesh_cid;
    sh.transform_cid = transform_cid;
    sh.light_cid = light_cid;
    sh.frame_cid = frame_cid;

    sh.lvp_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = 64, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 }, out_error);
    if (sh.lvp_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    if (!enabled) return true;

    const shadow_map_cid = core.ref.*.declare.?(core.ref, &c.ke_render_resource_desc{
        .name = "shadow_map",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, // filterable; depth in .r
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .clear_value = .{ 1.0, 1.0, 1.0, 1.0 }, // R=1 = far depth; alpha≠0 → override
    }, null);
    const shadow_depth_cid = core.ref.*.declare.?(core.ref, &c.ke_render_resource_desc{
        .name = "shadow_depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    sh.view = core.ref.*.resource_view.?(core.ref, "shadow_map");

    const sh_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(shadow_vs_wgsl), .byte_size = shadow_vs_wgsl.len, .entry_point = "shadow.vs" }, out_error);
    if (sh_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sh_vs);
    const sh_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(shadow_fs_wgsl), .byte_size = shadow_fs_wgsl.len, .entry_point = "shadow.fs" }, out_error);
    if (sh_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sh_fs);

    const sh_lvp_entry = c.ke_gpu_bind_group_layout_entry{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 };
    const sh_lvp_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{ .entry_count = 1, .entries = &sh_lvp_entry });
    const sh_obj_entry = c.ke_gpu_bind_group_layout_entry{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 1, .view_dimension = 0 };
    const sh_obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{ .entry_count = 1, .entries = &sh_obj_entry });

    const sh_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sh_vbl = c.ke_gpu_vertex_buffer_layout{ .stride = 11 * @sizeOf(f32), .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX, .attribute_count = 1, .attributes = &sh_attr };
    var shp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    shp.vertex_module = sh_vs;
    shp.fragment_module = sh_fs;
    shp.vertex_entry = "vs_main";
    shp.fragment_entry = "fs_main";
    shp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    shp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    shp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    shp.vertex_buffer_count = 1;
    shp.vertex_buffers = &sh_vbl;
    shp.blend_state.write_mask = 0x0F;
    shp.depth_stencil.depth_test_enabled = 1;
    shp.depth_stencil.depth_write_enabled = 1;
    shp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    shp.bind_group_layouts[0] = sh_lvp_bgl;
    shp.bind_group_layouts[1] = sh_obj_bgl;
    shp.bind_group_layout_count = 2;
    shp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    shp.color_target_count = 1;
    sh.pipeline = dev.create_render_pipeline.?(dev, &shp);
    if (sh.pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "shadow pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    const sh_lvp_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = sh.lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 };
    sh.lvp_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_lvp_bgl, .entry_count = 1, .entries = &sh_lvp_bg_entry }, out_error);
    if (sh.lvp_bg == c.KE_GPU_INVALID_HANDLE) return false;

    sh.obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = UNIFORM_STRIDE * MAX_DRAWS, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 }, out_error);
    if (sh.obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const sh_obj_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = sh.obj_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ShadowObj), .texture_view = 0, .sampler = 0 };
    sh.obj_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_obj_bgl, .entry_count = 1, .entries = &sh_obj_bg_entry }, out_error);
    if (sh.obj_bg == c.KE_GPU_INVALID_HANDLE) return false;

    sh.writes = .{ "shadow_map", "shadow_depth" };
    sh.io = std.mem.zeroes(c.ke_render_pass_io);
    sh.io.writes = @ptrCast(&sh.writes);
    sh.io.writes_count = 2;
    sh.io.cmd_slot = 1; // shadow pass → frame command slot 1 (before forward)
    sh.access = .{
        .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };
    return true;
}
