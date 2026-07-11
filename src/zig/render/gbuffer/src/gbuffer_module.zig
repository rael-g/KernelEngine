const std = @import("std");
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const gpa = std.heap.c_allocator;

// Deferred G-buffer encode pass — the opaque path's first half. Draws every
// mesh through the encode pipeline (mat_test_flat_gbuffer), writing the surface
// (albedo/metallic/normal/roughness/ao/emissive) into 3 color targets + depth.
// No lighting: the deferred_lighting pass reads these back and shades. Unlike
// forward, this pass needs no shadow/ibl/cluster/skybox handles — encode is
// pure surface capture.
//
// Target layout (must match gbuffer.slang + deferred_lighting.slang):
//   RT0 RGBA8:   albedo.rgb, metallic
//   RT1 RGBA8:   octNormal.xy, roughness, ao
//   RT2 RGBA16F: emissive.rgb, alpha
// Depth32Float is written here and sampled by deferred to reconstruct position.
//
// A standalone plugin: talks to the rest of the render pipeline only through
// the borrowed ke_render_core/ke_runtime handles passed to create() — it never
// sees another pass's private struct.

const vs_wgsl = @embedFile("mat_test_flat_gbuffer.vs.wgsl");
const fs_wgsl = @embedFile("mat_test_flat_gbuffer.fs.wgsl");

// Duplicated from the other pass modules per the decoupling precedent (see
// shadow_module.zig): small shared constants kept local, not imported.
const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform. Matches forward_common.slang PerObject.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

const GBufferModule = struct {
    core: *c.ke_render_core = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,

    mesh_cid: c.ke_component_id = undefined,
    transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,

    // Re-queried via core.get_or_create_pipeline every record() call — see
    // forward_module.zig's ForwardModule.pipeline_params for why a handle
    // cached once at setup can't observe the async real-PSO upgrade.
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    // The encode shader binds only set 1 (material) + set 2 (object); set 0 is
    // an empty layout so the positional bind_group_layouts array has no hole.
    empty_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    empty_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,

    writes: [4][*c]const u8 = undefined, // gbuffer_albedo/normal/emissive + depth
    io: c.ke_render_pass_io = undefined,
    access: [8]c.ke_component_access = undefined, // 3 gbuffer + depth writes; mesh/transform/camera/frame reads
    access_count: u32 = 0,
    // Resolved single-threaded by the runtime before the wave dispatches; the
    // body then reads plain memory via ke_system_ctx_view and touches the ECS
    // not at all.
    queries: [2]c.ke_query_decl = undefined, // [camera, transform], [mesh, transform]
};

// Left-handed view from a camera transform (identity rotation → look at origin;
// otherwise the world-matrix basis). Duplicated from forward_module.zig per the
// decoupling precedent so the encode pass agrees on view space independently.
fn cameraView(cam_tc: *const c.ke_transform_component) zm.Mat {
    const eye = zm.f32x4(cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0);
    const q = cam_tc.rotation;
    if (@abs(q.x) < 1e-6 and @abs(q.y) < 1e-6 and @abs(q.z) < 1e-6)
        return zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0));
    const m = cam_tc.world_matrix.m;
    const fwd = zm.f32x4(-m[8], -m[9], -m[10], 0);
    const up = zm.f32x4(m[4], m[5], m[6], 0);
    return zm.lookToLh(eye, fwd, up);
}

fn makePerspective(ndc: c.ke_ndc_convention, fovy: f32, aspect: f32, near: f32, far: f32) zm.Mat {
    var p = if (ndc.z_zero_to_one != 0)
        zm.perspectiveFovLh(fovy, aspect, near, far)
    else
        zm.perspectiveFovLhGl(fovy, aspect, near, far);
    if (ndc.y_flip != 0) p[1][1] = -p[1][1];
    return p;
}

inline fn moduleOf(user: ?*anyopaque) *GBufferModule {
    return @alignCast(@ptrCast(user.?));
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const gb = moduleOf(user);
    const core = gb.core;

    // View 0 = [camera, transform]; the first match is the active camera.
    var cam_segc: usize = 0;
    const cam_segs = c.ke_system_ctx_view(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, ctx, &gb.io);
    if (pc == null) return;

    // No camera — open/close so the G-buffer targets are cleared, then bail.
    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return;
    }

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const view = cameraView(cam_tc);
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = makePerspective(gb.ndc, fov_rad, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &gb.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, gb.empty_bg, null, 0); // set 0: empty (encode uses only sets 1+2)

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
            // BLEND materials are the transparent-forward pass's exclusive draws;
            // this pass never encodes them (a G-buffer holds one surface per pixel,
            // and blended fragments can't be adjudicated to a single one).
            if (core.*.material_alpha_mode.?(core, meshes[i].material) == c.KE_ALPHA_MODE_BLEND) continue;

            var vbo: c.ke_gpu_buffer = 0;
            var ibo: c.ke_gpu_buffer = 0;
            var idx_count: u32 = 0;
            if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;

            const model = zm.loadMat(tcs[i].world_matrix.m[0..]);
            const mvp = zm.mul(model, view_proj);
            var u: PerObject = undefined;
            zm.storeMat(u.mvp[0..], mvp);
            zm.storeMat(u.model[0..], model);
            const offset: u32 = draw_idx * UNIFORM_STRIDE;
            core.*.upload.?(core, gb.obj_uniform, offset, &u, @sizeOf(PerObject));

            const mat_bg = core.*.material_bind_group.?(core, meshes[i].material);
            rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
            rp.*.set_bind_group.?(rp, 2, gb.obj_bind_group, &offset, 1); // set 2: per-object
            rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
            rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
            rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
            draw_idx += 1;
        }
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn setup(gb: *GBufferModule, dev: *c.ke_gpu_device, core: *c.ke_render_core,
         ndc: c.ke_ndc_convention, mesh_cid: c.ke_component_id, transform_cid: c.ke_component_id,
         camera_cid: c.ke_component_id, frame_cid: c.ke_component_id, out_error: [*c][*c]c.ke_error) bool {
    gb.core = core;
    gb.device = dev;
    gb.ndc = ndc;
    gb.mesh_cid = mesh_cid;
    gb.transform_cid = transform_cid;
    gb.camera_cid = camera_cid;

    // Set 0 — empty: the encode shader binds only material (set 1) + object
    // (set 2), but the pipeline's positional layout array must fill index 0.
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

    // Set 2 — per-object transform ring (dynamic offset, vertex stage).
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

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &attrs,
    };

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(vs_wgsl),
        .byte_size = vs_wgsl.len,
        .entry_point = "mat_test_flat_gbuffer.vs",
    }, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(fs_wgsl),
        .byte_size = fs_wgsl.len,
        .entry_point = "mat_test_flat_gbuffer.fs",
    }, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, fs);

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    pp.blend_state.write_mask = 0x0F; // opaque encode, no blend
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 1;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    pp.bind_group_layouts[0] = gb.empty_bgl; // set 0: empty
    pp.bind_group_layouts[1] = core.*.material_layout.?(core); // set 1: per-material
    pp.bind_group_layouts[2] = obj_bgl; // set 2: per-object
    pp.bind_group_layout_count = 3;
    // MRT: the three G-buffer targets, in SV_Target order (matches gbuffer.slang
    // and the io.writes order below).
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM; // albedo + metallic
    pp.color_target_formats[1] = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM; // octNormal + roughness + ao
    pp.color_target_formats[2] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT; // emissive + alpha
    pp.color_target_count = 3;
    gb.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &gb.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
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

    // Declare the G-buffer targets (all relative-to-backbuffer) + the depth
    // buffer. depth is declared with SAMPLED usage (resource_table.zig) so the
    // deferred pass can read it back to reconstruct position.
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

    // Writes in SV_Target order (albedo, normal, emissive) + depth. ctxBeginRender
    // builds color attachments in this order, so it must match the pipeline's
    // color_target_formats and gbuffer.slang's SV_Target indices.
    gb.writes = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth" };
    gb.io = std.mem.zeroes(c.ke_render_pass_io);
    gb.io.writes = @ptrCast(&gb.writes);
    gb.io.writes_count = 4;
    gb.io.cmd_slot = 3; // after cull (slot 2), before deferred-lighting

    // frame_cid brackets the pass inside the frame barrier (begin writes it,
    // every pass reads it, end writes it), so begin_frame strictly precedes and
    // end_frame strictly follows this pass — same as every other pass module.
    gb.access = .{
        .{ .cid = albedo_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = normal_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = emissive_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };
    gb.access_count = 8;

    // Data the body reads through resolved views. Index order is the
    // query_index passed to ke_system_ctx_view.
    const rd = c.KE_ACCESS_READ;
    gb.queries = std.mem.zeroes([2]c.ke_query_decl);
    gb.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    gb.queries[0].terms[1] = .{ .cid = transform_cid, .access = rd };
    gb.queries[0].term_count = 2;
    gb.queries[1].terms[0] = .{ .cid = mesh_cid, .access = rd };
    gb.queries[1].terms[1] = .{ .cid = transform_cid, .access = rd };
    gb.queries[1].term_count = 2;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_gbuffer) callconv(.c) void {
    const gb: *GBufferModule = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(gb);
}

export fn ke_render_gbuffer_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_core,
                                    device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention,
                                    mesh_cid: c.ke_component_id, transform_cid: c.ke_component_id,
                                    camera_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_gbuffer_handle {
    const empty = c.ke_render_gbuffer_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;

    const gb = gpa.create(GBufferModule) catch return empty;
    gb.* = .{};
    if (!setup(gb, dev, core_ref, ndc, mesh_cid, transform_cid, camera_cid, frame_cid, out_error)) {
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
