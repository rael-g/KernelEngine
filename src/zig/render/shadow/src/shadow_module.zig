const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

// Shadow-depth pass — a standalone plugin: talks to the rest of the render
// pipeline only through the borrowed ke_render_service/ke_runtime handles passed
// to create() — it never sees another pass's private struct. It publishes its
// outputs ("shadow_map" view, "shadow_lvp" buffer) through the named-resource
// table; deferred/forward resolve them by name. When `enabled` is false,
// create() still publishes the tiny "shadow_lvp" uniform (a shading shader
// samples the shadow hook unconditionally; a neutral-default resource makes it
// a no-op) but none of the expensive resources (shadow_map/shadow_depth render
// targets, pipeline, per-draw buffers, the "render.shadow" system) exist.

const SHADOW_RES = 1024; // shadow map resolution

// Duplicated from render_module.zig rather than shared, matching the
// decoupling precedent already established in cluster_feature.slang (its own
// header comment: "Duplicated rather than shared via import to keep this
// feature decoupled from the pass file").
const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Per-object model for the shadow pass (set 1).
const ShadowObj = extern struct { model: [16]f32 };


const ShadowModule = struct {
    enabled: bool = false,

    // Borrowed cross-cutting refs, captured once at setup so the system body
    // never reaches into the parent ModuleState.
    core: *c.ke_render_service = undefined,
    ndc: c.ke_ndc_convention = undefined,
    mesh_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    view: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE, // the shadow map's view — read by the forward's set-0 binding 3/5
    // Re-queried via core.get_or_create_pipeline every record() call — see
    // forward_module.zig's ForwardModule.pipeline_params for why a handle
    // cached once at setup can't observe the async real-PSO upgrade.
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    lvp_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE, // set 0 (this pass) AND read by the forward's binding 4
    lvp_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [2][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [6]c.ke_component_access = undefined,
    // Resolved single-threaded by the runtime before the wave dispatches; the
    // body then reads plain memory via ke_system_ctx_view and touches the ECS
    // not at all. Index order here is the query_index the body passes to it.
    queries: [2]c.ke_query_decl = undefined, // [directional_light], [mesh, transform]
};

// Orthographic light view-proj; the light source sits opposite the travel
// direction. Frustum extent 20, far plane 50.
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

// View 0 = [directional_light]; the first match is the active sun. Null when
// the scene declares no directional light — the caller skips the pass rather
// than shadowing from an invented direction.
fn lightDirOf(ctx: ?*c.ke_system_ctx) ?zm.Vec {
    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &segc);
    if (segc == 0 or segs[0].count == 0) return null;
    const dl: *const c.ke_directional_light_component = @ptrCast(@alignCast(segs[0].columns[0]));
    return zm.f32x4(dl.dir_x, dl.dir_y, dl.dir_z, 0.0);
}

inline fn moduleOf(user: ?*anyopaque) *ShadowModule {
    return @alignCast(@ptrCast(user.?));
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const sh = moduleOf(user);
    const core = sh.core;

    // No directional light means there is no directional shadow to render;
    // the map keeps whatever the previous frame left and consumers gate on
    // the same absence.
    const light_dir = lightDirOf(ctx) orelse return;

    const lvp = lightViewProj(sh.ndc, light_dir);
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    core.*.upload.?(core, sh.lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, ctx, &sh.io);
    if (pc == null) return;

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sh.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, sh.lvp_bg, null, 0);

    // View 1 = [mesh, transform], columns aligned. Per-draw uniform writes are
    // deferred by the core and replayed before the submit, so uploading inside
    // the draw loop still lands ahead of the draws that read it.
    var draw_idx: u32 = 0;
    var segc: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 1, &segc);
    var s: usize = 0;
    while (s < segc and draw_idx < MAX_DRAWS) : (s += 1) {
        const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const tcs: [*c]const c.ke_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count and draw_idx < MAX_DRAWS) : (i += 1) {
            var vbo: c.ke_gpu_buffer = 0;
            var ibo: c.ke_gpu_buffer = 0;
            var idx_count: u32 = 0;
            if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;

            var u: ShadowObj = undefined;
            @memcpy(u.model[0..], tcs[i].world_matrix.m[0..16]);
            const offset: u32 = draw_idx * UNIFORM_STRIDE;
            core.*.upload.?(core, sh.obj_uniform, offset, &u, @sizeOf(ShadowObj));

            rp.*.set_bind_group.?(rp, 1, sh.obj_bg, &offset, 1);
            rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
            rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
            rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
            draw_idx += 1;
        }
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Allocates lvp_uniform unconditionally (tiny, 64 bytes — shadow_feature.slang's
// neutral-default hook resource) and, only when `enabled`, the expensive
// resources: the shadow_map/shadow_depth render targets, the shadow pipeline,
// and the per-draw uniform ring.
fn setup(sh: *ShadowModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
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
    // Published under a name (not a *ShadowModule pointer) so any pass can bind
    // it without knowing this module's private struct — the same contract
    // "shadow_map" already uses for the shadow view below.
    _ = core.*.import_buffer.?(core, "shadow_lvp", sh.lvp_uniform, 64, null);

    if (!enabled) return true;

    const shadow_map_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
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
    const shadow_depth_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "shadow_depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    sh.view = core.*.resource_view.?(core, "shadow_map");

    // Neither the path nor the shader format is named here — core.load_shader
    // resolves both. The core owns the result; this pass never destroys it.
    const sh_vs = core.*.load_shader.?(core, "shadow", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (sh_vs == c.KE_GPU_INVALID_HANDLE) return false;
    const sh_fs = core.*.load_shader.?(core, "shadow", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (sh_fs == c.KE_GPU_INVALID_HANDLE) return false;

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
    sh.pipeline_params = shp;
    if (core.*.get_or_create_pipeline.?(core, &sh.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
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
    sh.io.cmd_slot = 1; // shadow pass → frame command slot 1 (before the opaque pass)
    sh.access = .{
        .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Data the body reads through resolved views. Index order is the
    // query_index passed to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    sh.queries = std.mem.zeroes([2]c.ke_query_decl);
    sh.queries[0].terms[0] = .{ .cid = light_cid, .access = rd };
    sh.queries[0].term_count = 1;
    sh.queries[1].terms[0] = .{ .cid = mesh_cid, .access = rd };
    sh.queries[1].terms[1] = .{ .cid = transform_cid, .access = rd };
    sh.queries[1].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_shadow) callconv(.c) void {
    const sh: *ShadowModule = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(sh);
}

export fn ke_render_shadow_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                   device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                   enabled: c.ke_bool, mesh_cid: c.ke_component_id,
                                   transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
                                   frame_cid: c.ke_component_id,
                                   out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_shadow_handle {
    const empty = c.ke_render_shadow_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const sh = gpa.create(ShadowModule) catch return empty;
    sh.* = .{};
    if (!setup(sh, dev, core_ref, ndc, enabled != 0, mesh_cid, transform_cid, light_cid, frame_cid, out_error)) {
        gpa.destroy(sh);
        return empty;
    }

    if (sh.enabled) {
        var params = std.mem.zeroes(c.ke_runtime_system_params);
        params.name = "render.shadow";
        params.phase = c.KE_PHASE_RENDER;
        params.queries = &sh.queries;
        params.query_count = sh.queries.len;
        params.access_list = &sh.access;
        params.access_count = sh.access.len;
        params.pinned_thread = 0;
        params.user_data = sh;
        params.execute = system;
        _ = rt.register_system.?(rt, &params, null);
    }

    return .{ .ref = @ptrCast(sh), .destroy = destroyHandle };
}
