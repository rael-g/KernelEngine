const std = @import("std");
const zm = @import("zmath");

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed.
pub const c = @cImport({
    @cInclude("kernel_engine/runtime/runtime.h");
    @cInclude("kernel_engine/runtime/system_ctx.h");
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/spatial/transform.h");
    @cInclude("kernel_engine/render/components.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
    @cInclude("kernel_engine/render/core/render_core_create.h");
    @cInclude("kernel_engine/render/core/render_module_create.h");
});

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

// The forward pass shaders, compiled Slang -> WGSL by CMake (one module per
// stage; a cross-stage uniform can't be declared twice in one WGSL module).
const forward_vs_wgsl = @embedFile("forward.vs.wgsl");
const forward_fs_wgsl = @embedFile("forward.fs.wgsl");
const skybox_vs_wgsl = @embedFile("skybox.vs.wgsl");
const skybox_fs_wgsl = @embedFile("skybox.fs.wgsl");
const shadow_vs_wgsl = @embedFile("shadow.vs.wgsl");
const shadow_fs_wgsl = @embedFile("shadow.fs.wgsl");

const SHADOW_RES = 1024; // shadow map resolution

const MAX_DRAWS = 64;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Set 2 — per-object transform (dynamic offset). Matches forward.slang PerObject.
const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

// Set 0 — per-frame camera + light + skybox view. Matches forward.slang PerFrame.
const PerFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32, // rgb, w = intensity
    ambient: [4]f32,
    sky_view_proj: [16]f32, // rotation-only view*proj for the skybox
    light_vp: [16]f32, // directional light view*proj (for shadow sampling)
    shadow_params: [4]f32, // x = 1 when a shadow map is active
};

// Unit cube positions (8 corners) + indices for the skybox.
const sky_verts = [_]f32{
    -1, -1, -1, 1, -1, -1, 1, 1, -1, -1, 1, -1,
    -1, -1, 1,  1, -1, 1,  1, 1, 1,  -1, 1, 1,
};
const sky_idx = [_]u16{
    0, 1, 2, 0, 2, 3, // -Z
    4, 6, 5, 4, 7, 6, // +Z
    0, 4, 5, 0, 5, 1, // -Y
    3, 2, 6, 3, 6, 7, // +Y
    0, 3, 7, 0, 7, 4, // -X
    1, 5, 6, 1, 6, 2, // +X
};

// Mirrors ke_directional_light_component (10 floats, see render/components.h).
const DirLight = extern struct {
    dir: [3]f32,
    rgb: [3]f32,
    intensity: f32,
    ambient: [3]f32,
};

// The device is borrowed (caller-owned); only the render core is owned here.
const ModuleState = struct {
    core: c.ke_render_core_handle,
    device: *c.ke_gpu_device,

    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    // Frame barrier: begin_frame WRITES "frame", every pass READS it, end_frame
    // WRITES it (write-after-read). W→R→W brackets all passes into one frame so
    // begin (clears the slot table + acquires the backbuffer) strictly precedes
    // every pass and end (submits) strictly follows; passes stay parallel (R/R).
    frame_cid: c.ke_component_id,
    begin_access: [2]c.ke_component_access, // WRITE backbuffer, WRITE frame
    clear_access: [2]c.ke_component_access, // WRITE backbuffer, READ frame
    end_access: [2]c.ke_component_access, // READ backbuffer, WRITE frame

    // Forward pass
    fwd_pipeline: c.ke_gpu_pipeline,
    fwd_obj_bind_group: c.ke_gpu_bind_group, // set 2, per-object (dynamic offset)
    fwd_obj_uniform: c.ke_gpu_buffer,
    fwd_frame_bind_group: c.ke_gpu_bind_group, // set 0, per-frame
    fwd_frame_uniform: c.ke_gpu_buffer,
    fwd_writes: [2][*c]const u8,
    fwd_reads: [1][*c]const u8,
    fwd_io: c.ke_render_pass_io,
    fwd_access: [9]c.ke_component_access,
    mesh_cid: c.ke_component_id,
    transform_cid: c.ke_component_id,
    camera_cid: c.ke_component_id,
    light_cid: c.ke_component_id,
    skybox_cid: c.ke_component_id,

    // Skybox (drawn inside the forward pass: clear → meshes → skybox depth-LEQUAL)
    sky_pipeline: c.ke_gpu_pipeline,
    sky_vbo: c.ke_gpu_buffer,
    sky_ibo: c.ke_gpu_buffer,
    frame_bgl: c.ke_gpu_bind_group_layout, // set 0 layout (rebuild bind group on env change)
    env_cubemap: c.ke_texture_handle, // currently bound env (default until a skybox is set)
    shadow_view: c.ke_gpu_texture_view, // the shadow map's view (for set 0 binding)

    // Shadow-depth pass (renders casters from the light POV into shadow_map)
    shadow_pipeline: c.ke_gpu_pipeline,
    shadow_lvp_uniform: c.ke_gpu_buffer, // set 0: light view-proj
    shadow_lvp_bg: c.ke_gpu_bind_group,
    shadow_obj_uniform: c.ke_gpu_buffer, // set 1: per-object model (dynamic offset)
    shadow_obj_bg: c.ke_gpu_bind_group,
    shadow_writes: [2][*c]const u8,
    shadow_io: c.ke_render_pass_io,
    shadow_access: [6]c.ke_component_access,
};

// Per-object model for the shadow pass (set 1).
const ShadowObj = extern struct { model: [16]f32 };

// Mirrors the framework SkyboxComponent (registered under "Skybox"): a cubemap
// texture handle.
const SkyboxComp = extern struct { cubemap: c.ke_texture_handle };

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

// ── Frame-boundary systems (ordered by the backbuffer tag-cid) ────────────────

fn beginFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.begin_frame.?(st.core.ref, null);
}

fn clearSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const pc = st.core.ref.*.begin_pass.?(st.core.ref, ctx, &st.io);
    if (pc == null) return;
    const rp = pc.*.begin_render.?(pc);
    rp.*.end.?(rp);
    st.core.ref.*.end_pass.?(st.core.ref, pc);
}

fn endFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.end_frame.?(st.core.ref, null);
}

// ── Shadow-depth pass ─────────────────────────────────────────────────────────
// Orthographic light view-proj; the light source sits opposite the travel
// direction. Matches the legacy bgfx ShadowRenderSystem (frustum 20, far 50).
fn lightViewProj(ldir_in: zm.Vec) zm.Mat {
    const ldir = zm.normalize3(ldir_in);
    const eye3 = ldir * zm.f32x4s(-25.0);
    const eye = zm.f32x4(eye3[0], eye3[1], eye3[2], 1.0);
    const up = if (@abs(ldir[1]) > 0.99) zm.f32x4(0, 0, 1, 0) else zm.f32x4(0, 1, 0, 0);
    const lview = zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), up);
    const lproj = zm.orthographicLh(20.0, 20.0, 0.1, 50.0);
    return zm.mul(lview, lproj);
}

fn lightDirOf(ctx: ?*c.ke_system_ctx, st: *ModuleState) zm.Vec {
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.light_cid, &ents, &data, &count);
    if (count == 0) return zm.f32x4(-0.4, -1.0, -0.3, 0.0);
    const dl: *const DirLight = @ptrCast(@alignCast(data));
    return zm.f32x4(dl.dir[0], dl.dir[1], dl.dir[2], 0.0);
}

fn shadowSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;
    const dev = st.device;

    const lvp = lightViewProj(lightDirOf(ctx, st));
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    dev.write_buffer.?(dev, st.shadow_lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, ctx, &st.shadow_io);
    if (pc == null) return;

    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        var u: ShadowObj = undefined;
        @memcpy(u.model[0..], tc.world_matrix.m[0..16]);
        dev.write_buffer.?(dev, st.shadow_obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(ShadowObj));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.shadow_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.shadow_lvp_bg, null, 0);
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        rp.*.set_bind_group.?(rp, 1, st.shadow_obj_bg, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// ── Forward mesh pass ─────────────────────────────────────────────────────────

fn forwardSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;
    const dev = st.device;

    // Camera: take the first camera entity + its transform.
    var cam_ents: [*c]c.ke_entity = undefined;
    var cam_data: ?*anyopaque = undefined;
    var cam_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.camera_cid, &cam_ents, &cam_data, &cam_count);
    if (cam_count == 0) return;
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_data));
    const cam_tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, cam_ents[0]) orelse return;
    const cam_tc: *const c.ke_transform_component = @ptrCast(@alignCast(cam_tc_raw));

    const pc = core.*.begin_pass.?(core, ctx, &st.fwd_io);
    if (pc == null) return;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    const eye = zm.f32x4(cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0);
    const q = cam_tc.rotation;
    // No rotation → look at the origin (the convention examples 01-04 rely on);
    // a rotated camera (free-look) derives its view from the rotation.
    const view = if (@abs(q.x) < 1e-6 and @abs(q.y) < 1e-6 and @abs(q.z) < 1e-6)
        zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0))
    else blk: {
        const rot = zm.f32x4(q.x, q.y, q.z, q.w);
        const fwd = zm.rotate(rot, zm.f32x4(0, 0, -1, 0));
        const up = zm.rotate(rot, zm.f32x4(0, 1, 0, 0));
        break :blk zm.lookToLh(eye, fwd, up);
    };
    // ke_camera_component.fov is in degrees (the cross-backend convention).
    const fov_rad = cam.fov * @as(f32, std.math.pi / 180.0);
    const proj = zm.perspectiveFovLh(fov_rad, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);

    // Skybox view: rotation-only (translation zeroed) × proj, so the cube stays
    // centred on the camera (infinite background).
    var vm: [16]f32 = undefined;
    zm.storeMat(vm[0..], view);
    vm[12] = 0;
    vm[13] = 0;
    vm[14] = 0;
    const sky_vp = zm.mul(zm.loadMat(vm[0..]), proj);

    // Environment cubemap from the first skybox entity (default black otherwise);
    // rebuild set 0 only when the bound environment changes.
    var sky_ents: [*c]c.ke_entity = undefined;
    var sky_data: ?*anyopaque = undefined;
    var sky_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.skybox_cid, &sky_ents, &sky_data, &sky_count);
    const want_env: c.ke_texture_handle = if (sky_count != 0)
        (@as(*const SkyboxComp, @ptrCast(@alignCast(sky_data)))).cubemap
    else
        .{ .idx = c.KE_HANDLE_NONE };
    if (want_env.idx != st.env_cubemap.idx) {
        st.env_cubemap = want_env;
        rebuildFrameBindGroup(st);
    }

    // Per-frame: camera + first directional light (defaults when none present).
    var frame: PerFrame = .{
        .camera_pos = .{ cam_tc.position.x, cam_tc.position.y, cam_tc.position.z, 1.0 },
        .light_dir = .{ -0.4, -1.0, -0.3, 0.0 },
        .light_color = .{ 1.0, 1.0, 1.0, 1.0 },
        .ambient = .{ 0.03, 0.03, 0.03, 0.0 },
        .sky_view_proj = undefined,
        .light_vp = undefined,
        .shadow_params = .{ 1.0, 0.0, 0.0, 0.0 }, // x = shadow active
    };
    zm.storeMat(frame.sky_view_proj[0..], sky_vp);
    // Same light view-proj the shadow pass used, for the forward's shadow lookup.
    zm.storeMat(frame.light_vp[0..], lightViewProj(lightDirOf(ctx, st)));
    var li_ents: [*c]c.ke_entity = undefined;
    var li_data: ?*anyopaque = undefined;
    var li_count: usize = 0;
    c.ke_system_ctx_query(ctx, st.light_cid, &li_ents, &li_data, &li_count);
    if (li_count != 0) {
        const dl: *const DirLight = @ptrCast(@alignCast(li_data));
        frame.light_dir = .{ dl.dir[0], dl.dir[1], dl.dir[2], 0.0 };
        frame.light_color = .{ dl.rgb[0], dl.rgb[1], dl.rgb[2], dl.intensity };
        frame.ambient = .{ dl.ambient[0], dl.ambient[1], dl.ambient[2], 0.0 };
    }
    dev.write_buffer.?(dev, st.fwd_frame_uniform, 0, &frame, @sizeOf(PerFrame));

    // Meshes: build + upload one uniform region per draw (queue writes land before
    // the recorded draws, so each dynamic offset reads its own object).
    var ents: [*c]c.ke_entity = undefined;
    var data: ?*anyopaque = undefined;
    var count: usize = 0;
    c.ke_system_ctx_query(ctx, st.mesh_cid, &ents, &data, &count);
    const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(data));
    const n: u32 = @intCast(@min(count, MAX_DRAWS));

    var i: u32 = 0;
    while (i < n) : (i += 1) {
        const tc_raw = c.ke_system_ctx_get(ctx, st.transform_cid, ents[i]) orelse continue;
        const tc: *const c.ke_transform_component = @ptrCast(@alignCast(tc_raw));
        const model = zm.loadMat(tc.world_matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);

        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        dev.write_buffer.?(dev, st.fwd_obj_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(PerObject));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.fwd_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.fwd_frame_bind_group, null, 0); // set 0: per-frame
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        const mat_bg = core.*.material_bind_group.?(core, meshes[i].material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0); // set 1: per-material
        rp.*.set_bind_group.?(rp, 2, st.fwd_obj_bind_group, &offset, 1); // set 2: per-object
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }

    // Skybox last — depth LEQUAL, no depth write: fills only the background pixels
    // the opaque meshes did not cover, within the same render pass (no load-op).
    rp.*.set_pipeline.?(rp, st.sky_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.fwd_frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, st.sky_vbo, 0);
    rp.*.set_index_buffer.?(rp, st.sky_ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
    rp.*.draw_indexed.?(rp, sky_idx.len, 1, 0, 0, 0);

    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// Builds set 0 (per-frame uniform + env cubemap + sampler). Called at setup and
// whenever the bound environment cubemap changes (rare — at scene load).
fn rebuildFrameBindGroup(st: *ModuleState) void {
    const dev = st.device;
    const core = st.core.ref;
    const env_view = core.*.texture_view.?(core, st.env_cubemap);
    const smp = core.*.sampler.?(core);
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.fwd_frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = env_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = st.shadow_view, .sampler = 0 },
    };
    st.fwd_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.frame_bgl,
        .entry_count = 4,
        .entries = &entries,
    });
}

fn forwardSetup(st: *ModuleState, e: *c.ke_ecs, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    st.mesh_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_MESH, @sizeOf(c.ke_mesh_component));
    st.transform_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
    st.camera_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_CAMERA, @sizeOf(c.ke_camera_component));
    st.light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, @sizeOf(c.ke_directional_light_component));
    st.skybox_cid = e.component_register.?(e, "Skybox", @sizeOf(SkyboxComp));
    st.env_cubemap = .{ .idx = c.KE_HANDLE_NONE }; // default (black) cube until a skybox is set

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(forward_vs_wgsl),
        .byte_size = forward_vs_wgsl.len,
        .entry_point = "forward.vs",
    }, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, vs);

    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(forward_fs_wgsl),
        .byte_size = forward_fs_wgsl.len,
        .entry_point = "forward.fs",
    }, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, fs);

    // Set 2 — per-object transform (dynamic offset, vertex stage).
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

    // Set 0 — per-frame uniform (vs reads sky_view_proj; fs reads camera/light) +
    // environment cubemap + sampler (fs, for skybox + IBL).
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 2, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 }, // shadow map (2D R32F)
    };
    const frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &frame_bgl_entries,
    });
    st.frame_bgl = frame_bgl;

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
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE; // winding-agnostic for the first pass; depth sorts
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &vbl;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 1;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    pp.bind_group_layouts[0] = frame_bgl; // set 0: per-frame (camera + light)
    pp.bind_group_layouts[1] = st.core.ref.*.material_layout.?(st.core.ref); // set 1: per-material
    pp.bind_group_layouts[2] = obj_bgl; // set 2: per-object (transform)
    pp.bind_group_layout_count = 3;
    pp.color_target_format = 0; // swapchain
    st.fwd_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.fwd_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "forward pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    // Set 2 — per-object ring (one dynamic-offset region per draw).
    st.fwd_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = st.fwd_obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    st.fwd_obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    });

    // ── Shadow-depth pass: targets + pipeline + uniforms ──────────────────
    const shadow_map_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "shadow_map",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT, // filterable; depth in .r
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    const shadow_depth_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "shadow_depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = SHADOW_RES,
        .height = SHADOW_RES,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    st.shadow_view = st.core.ref.*.resource_view.?(st.core.ref, "shadow_map");

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
    shp.color_target_format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    st.shadow_pipeline = dev.create_render_pipeline.?(dev, &shp);
    if (st.shadow_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "shadow pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.shadow_lvp_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = 64, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 });
    const sh_lvp_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.shadow_lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 };
    st.shadow_lvp_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_lvp_bgl, .entry_count = 1, .entries = &sh_lvp_bg_entry });

    st.shadow_obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .initial_data = null, .size = UNIFORM_STRIDE * MAX_DRAWS, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = 0 });
    const sh_obj_bg_entry = c.ke_gpu_bind_group_entry{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = st.shadow_obj_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(ShadowObj), .texture_view = 0, .sampler = 0 };
    st.shadow_obj_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{ .layout = sh_obj_bgl, .entry_count = 1, .entries = &sh_obj_bg_entry });

    st.shadow_writes = .{ "shadow_map", "shadow_depth" };
    st.shadow_io = std.mem.zeroes(c.ke_render_pass_io);
    st.shadow_io.writes = @ptrCast(&st.shadow_writes);
    st.shadow_io.writes_count = 2;
    st.shadow_io.cmd_slot = 1; // shadow pass → frame command slot 1 (before forward)
    st.shadow_access = .{
        .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };

    // Set 0 — per-frame uniform + env cubemap + sampler + shadow map. The bind
    // group is rebuilt (rebuildFrameBindGroup) when the bound environment changes.
    st.fwd_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    rebuildFrameBindGroup(st);

    // Skybox pipeline (set 0 only): position-only cube, depth LEQUAL, no write.
    const sky_vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_vs_wgsl),
        .byte_size = skybox_vs_wgsl.len,
        .entry_point = "skybox.vs",
    }, out_error);
    if (sky_vs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_vs);
    const sky_fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{
        .code = @ptrCast(skybox_fs_wgsl),
        .byte_size = skybox_fs_wgsl.len,
        .entry_point = "skybox.fs",
    }, out_error);
    if (sky_fs == c.KE_GPU_INVALID_HANDLE) return false;
    defer dev.destroy_shader_module.?(dev, sky_fs);

    const sky_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sky_vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 3 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 1,
        .attributes = &sky_attr,
    };
    var skp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    skp.vertex_module = sky_vs;
    skp.fragment_module = sky_fs;
    skp.vertex_entry = "vs_main";
    skp.fragment_entry = "fs_main";
    skp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    skp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    skp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    skp.vertex_buffer_count = 1;
    skp.vertex_buffers = &sky_vbl;
    skp.blend_state.write_mask = 0x0F;
    skp.depth_stencil.depth_test_enabled = 1;
    skp.depth_stencil.depth_write_enabled = 0; // skybox never occludes
    skp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS_EQUAL;
    skp.bind_group_layouts[0] = frame_bgl;
    skp.bind_group_layout_count = 1;
    skp.color_target_format = 0;
    st.sky_pipeline = dev.create_render_pipeline.?(dev, &skp);
    if (st.sky_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "skybox: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }
    st.sky_vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_verts,
        .size = @sizeOf(@TypeOf(sky_verts)),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    st.sky_ibo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = &sky_idx,
        .size = @sizeOf(@TypeOf(sky_idx)),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });

    // Transient depth target, sized to the backbuffer (the core resolves the
    // scale against its current swapchain size).
    const depth_cid = st.core.ref.*.declare.?(st.core.ref, &c.ke_render_resource_desc{
        .name = "depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0,
        .height = 0,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);

    st.fwd_writes = .{ "backbuffer", "depth" };
    st.fwd_reads = .{"shadow_map"};
    st.fwd_io = std.mem.zeroes(c.ke_render_pass_io);
    st.fwd_io.writes = @ptrCast(&st.fwd_writes);
    st.fwd_io.writes_count = 2;
    st.fwd_io.reads = @ptrCast(&st.fwd_reads);
    st.fwd_io.reads_count = 1;
    st.fwd_io.cmd_slot = 2; // forward pass → frame command slot 2 (after shadow)

    const bb_cid = st.core.ref.*.cid.?(st.core.ref, "backbuffer");
    st.fwd_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.camera_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.skybox_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.core.ref.*.cid.?(st.core.ref, "shadow_map"), .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };
    return true;
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8, access: [*c]c.ke_component_access,
               access_count: u32, user: *ModuleState, exec: ExecFn) void {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = name;
    params.phase = c.KE_PHASE_RENDER;
    params.access_list = access;
    params.access_count = access_count;
    params.pinned_thread = 0;
    params.user_data = user;
    params.execute = exec;
    _ = rt.register_system.?(rt, &params, null);
}

export fn ke_render_module_core(module: ?*c.ke_render_module) callconv(.c) ?*c.ke_render_core {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return null));
    return st.core.ref;
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    if (st.core.destroy) |d| d(st.core.ref);
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, device: ?*c.ke_gpu_device,
                                  default_passes: c.ke_bool, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const dev = device orelse return empty;

    const core_h = c.ke_render_core_create(dev, e, out_error);
    if (core_h.ref == null) return empty;

    const st = gpa.create(ModuleState) catch {
        if (core_h.destroy) |d| d(core_h.ref);
        return empty;
    };
    st.core = core_h;
    st.device = dev;
    st.bb_writes = .{"backbuffer"};
    st.io = std.mem.zeroes(c.ke_render_pass_io);
    st.io.writes = @ptrCast(&st.bb_writes);
    st.io.writes_count = 1;
    st.io.cmd_slot = 0; // clear pass → frame command slot 0

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    // Zero-size tag for the frame barrier (see ModuleState.frame_cid).
    st.frame_cid = e.component_register.?(e, "render.frame", 0);
    st.begin_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };
    st.clear_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };
    st.end_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };

    // No pass is imposed. default_passes registers the conventional chain;
    // otherwise the game wires its own passes. A failed setup (e.g. a bad shader)
    // fails loudly via out_error — it is never silently skipped.
    if (default_passes != 0) {
        if (!forwardSetup(st, e, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        registerSys(rt, "render.begin_frame", &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", &st.clear_access, st.clear_access.len, st, clearSys);
        registerSys(rt, "render.shadow", &st.shadow_access, st.shadow_access.len, st, shadowSys);
        registerSys(rt, "render.forward", &st.fwd_access, st.fwd_access.len, st, forwardSys);
        registerSys(rt, "render.end_frame", &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
