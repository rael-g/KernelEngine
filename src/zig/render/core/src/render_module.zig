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

const MAX_DRAWS = 64;
const UNIFORM_STRIDE = 256; // dynamic-offset alignment (>= minUniformBufferOffsetAlignment)

// Per-object uniform; layout matches forward.slang's Globals (std140).
const Uniform = extern struct {
    mvp: [16]f32,
    model: [16]f32,
    light_dir: [4]f32,
    base_color: [4]f32,
};

// The device is borrowed (caller-owned); only the render core is owned here.
const ModuleState = struct {
    core: c.ke_render_core_handle,
    device: *c.ke_gpu_device,

    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    bb_write_access: [1]c.ke_component_access,
    bb_read_access: [1]c.ke_component_access,

    // Forward pass
    fwd_pipeline: c.ke_gpu_pipeline,
    fwd_bind_group: c.ke_gpu_bind_group,
    fwd_uniform: c.ke_gpu_buffer,
    fwd_writes: [2][*c]const u8,
    fwd_io: c.ke_render_pass_io,
    fwd_access: [5]c.ke_component_access,
    mesh_cid: c.ke_component_id,
    transform_cid: c.ke_component_id,
    camera_cid: c.ke_component_id,
};

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
    const view = zm.lookAtLh(eye, zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 1, 0, 0));
    const proj = zm.perspectiveFovLh(cam.fov, aspect, cam.near_plane, cam.far_plane);
    const view_proj = zm.mul(view, proj);

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

        var u: Uniform = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        u.light_dir = .{ -0.4, -1.0, -0.3, 0.0 };
        u.base_color = meshes[i].color;
        dev.write_buffer.?(dev, st.fwd_uniform, i * UNIFORM_STRIDE, &u, @sizeOf(Uniform));
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.fwd_pipeline);
    i = 0;
    while (i < n) : (i += 1) {
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count) == 0) continue;
        const offset: u32 = i * UNIFORM_STRIDE;
        rp.*.set_bind_group.?(rp, 0, st.fwd_bind_group, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

fn forwardSetup(st: *ModuleState, e: *c.ke_ecs, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    st.mesh_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_MESH, @sizeOf(c.ke_mesh_component));
    st.transform_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
    st.camera_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_CAMERA, @sizeOf(c.ke_camera_component));

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

    const bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0,
        .visibility = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 1,
    };
    const bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &bgl_entry,
    });

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 6 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 2,
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
    pp.bind_group_layouts[0] = bgl;
    pp.bind_group_layout_count = 1;
    pp.color_target_format = 0; // swapchain
    st.fwd_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.fwd_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "forward pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.fwd_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });

    const bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = st.fwd_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(Uniform),
        .texture_view = 0,
        .sampler = 0,
    };
    st.fwd_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = bgl,
        .entry_count = 1,
        .entries = &bg_entry,
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
    st.fwd_io = std.mem.zeroes(c.ke_render_pass_io);
    st.fwd_io.writes = @ptrCast(&st.fwd_writes);
    st.fwd_io.writes_count = 2;

    const bb_cid = st.core.ref.*.cid.?(st.core.ref, "backbuffer");
    st.fwd_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.camera_cid, .access = c.KE_ACCESS_READ },
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

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    st.bb_write_access = .{.{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE }};
    st.bb_read_access = .{.{ .cid = bb_cid, .access = c.KE_ACCESS_READ }};

    // No pass is imposed. default_passes registers the conventional chain;
    // otherwise the game wires its own passes. A failed setup (e.g. a bad shader)
    // fails loudly via out_error — it is never silently skipped.
    if (default_passes != 0) {
        if (!forwardSetup(st, e, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        registerSys(rt, "render.begin_frame", &st.bb_write_access, 1, st, beginFrameSys);
        registerSys(rt, "render.clear", &st.bb_write_access, 1, st, clearSys);
        registerSys(rt, "render.forward", &st.fwd_access, st.fwd_access.len, st, forwardSys);
        registerSys(rt, "render.end_frame", &st.bb_read_access, 1, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
