const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;

const MAX_DRAWS = 512;
const UNIFORM_STRIDE = 256;

const PerObject = extern struct {
    mvp: [16]f32,
    model: [16]f32,
};

const PerFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32,
    ambient: [4]f32,
    shadow_params: [4]f32,
    viewport: [4]f32,
    view: [16]f32,
};

const Draw = struct {
    mesh: *const c.ke_mesh_component,
    world: *const c.ke_world_transform_component,
    view_distance_sq: f32,
};

fn drawFartherFirst(_: void, a: Draw, b: Draw) bool {
    return a.view_distance_sq > b.view_distance_sq;
}

fn collectDraws(
    core: *c.ke_render_service,
    cam: *const c.ke_camera_component,
    view: zm.Mat,
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
            if (core.material_alpha_mode.?(core, meshes[i].material) != c.KE_ALPHA_MODE_BLEND) continue;
            const wm = wts[i].matrix.m;
            const wp = zm.f32x4(wm[12], wm[13], wm[14], 1.0);
            const view_pos = zm.mul(wp, view);
            out[count] = .{ .mesh = @ptrCast(&meshes[i]), .world = @ptrCast(&wts[i]), .view_distance_sq = view_pos[0] * view_pos[0] + view_pos[1] * view_pos[1] + view_pos[2] * view_pos[2] };
            count += 1;
        }
    }
    std.sort.pdq(Draw, out[0..count], {}, drawFartherFirst);
    return count;
}

const ForwardModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    camera: *c.ke_render_camera = undefined,
    logger: ?*c.ke_logger = null,

    ibl_enabled: bool = true,

    mesh_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    camera_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    ambient_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    pipeline_template: c.ke_gpu_render_pipeline_params = undefined,
    attrs: [4]c.ke_gpu_vertex_attribute = undefined,
    vbl: c.ke_gpu_vertex_buffer_layout = undefined,
    frame_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    obj_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    obj_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    obj_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    env_cubemap: c.ke_texture_handle = .{ .bits = c.KE_HANDLE_NONE },

    draws: [MAX_DRAWS]Draw = undefined,

    writes: [2][*c]const u8 = undefined,
    reads: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [12]c.ke_component_access = undefined,
    access_count: u32 = 0,
    queries: [5]c.ke_query_decl = undefined,

    fn resolvePipeline(fwd: *ForwardModule, shader: [*c]const u8) bool {
        var name_buf: [MAX_SHADER_QUALIFIED]u8 = undefined;
        const name = std.fmt.bufPrintZ(&name_buf, "{s}.{s}", .{ std.mem.span(shader), PASS_NAME }) catch return false;
        const vs = fwd.core.*.load_shader.?(fwd.core, name.ptr, c.KE_GPU_SHADER_STAGE_VERTEX, null);
        if (vs == c.KE_GPU_INVALID_HANDLE) return false;
        const fs = fwd.core.*.load_shader.?(fwd.core, name.ptr, c.KE_GPU_SHADER_STAGE_FRAGMENT, null);
        if (fs == c.KE_GPU_INVALID_HANDLE) return false;
        fwd.pipeline_template.vertex_module = vs;
        fwd.pipeline_template.fragment_module = fs;
        return true;
    }
};

const PASS_NAME = "forward";
const DEFAULT_MATERIAL_SHADER = "standard";
const MAX_SHADER_QUALIFIED = 128;

fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_forward", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *ForwardModule {
    return @alignCast(@ptrCast(user.?));
}

fn rebuildFrameBindGroup(fwd: *ForwardModule) void {
    const dev = fwd.device;
    const core = fwd.core;
    const env_view = core.*.texture_view.?(core, fwd.env_cubemap);
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = c.KE_HANDLE_NONE });
    const hdr_opaque_view = core.*.resource_view.?(core, "hdr_opaque");
    const smp = core.*.sampler.?(core);

    const shadow_view_raw = core.*.resource_view.?(core, "shadow_map");
    const shadow_tex_view = if (shadow_view_raw != c.KE_GPU_INVALID_HANDLE) shadow_view_raw else white_view;
    const shadow_lvp_buf = core.*.resource_buffer.?(core, "shadow_lvp");
    const shadow_lvp_size = core.*.resource_buffer_size.?(core, "shadow_lvp");
    const ibl_view = if (fwd.ibl_enabled) env_view else black_cube_view;

    const entries = [8]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = fwd.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(PerFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_opaque_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = shadow_lvp_buf, .buffer_offset = 0, .buffer_size = shadow_lvp_size, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };

    var err: ?*c.ke_error = null;
    fwd.frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = fwd.frame_bgl,
        .entry_count = 8,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(fwd.logger, err, "transparent-forward frame bind group");
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const fwd = moduleOf(user);
    const core = fwd.core;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);
    if (cam_segc == 0 or cam_segs[0].count == 0) return true;

    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    const pc = core.*.begin_pass.?(core, &fwd.io);
    if (pc == null) return true;

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);

    const enc = pc.*.encoder.?(pc);
    const hdr_tex = core.*.resource_texture.?(core, "hdr");
    const hdr_opaque_tex = core.*.resource_texture.?(core, "hdr_opaque");
    enc.*.copy_texture_to_texture.?(enc, hdr_tex, hdr_opaque_tex, bw, bh);

    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;
    var view_m: c.ke_mat4 = undefined;
    fwd.camera.view.?(fwd.camera, &cam_wt.matrix, &view_m);
    var proj_m: c.ke_mat4 = undefined;
    fwd.camera.projection.?(fwd.camera, cam, aspect, &proj_m);
    const view = zm.loadMat(&view_m.m);
    const view_proj = zm.mul(view, zm.loadMat(&proj_m.m));

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const want_env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const c.ke_skybox_component, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    if (want_env.bits != fwd.env_cubemap.bits or fwd.frame_bind_group == c.KE_GPU_INVALID_HANDLE) {
        fwd.env_cubemap = want_env;
        rebuildFrameBindGroup(fwd);
    }

    var frame: PerFrame = .{
        .camera_pos = .{ cam_wt.matrix.m[12], cam_wt.matrix.m[13], cam_wt.matrix.m[14], 1.0 },
        .light_dir = .{ 0.0, 0.0, 0.0, 0.0 },
        .light_color = .{ 0.0, 0.0, 0.0, 0.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 },
        .viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 },
        .view = undefined,
    };
    zm.storeMat(frame.view[0..], view);

    var li_segc: usize = 0;
    const li_segs = ctx.?.view.?(ctx, 2, &li_segc);
    if (li_segc != 0 and li_segs[0].count != 0) {
        const d: *const c.ke_directional_light_component = @ptrCast(@alignCast(li_segs[0].columns[0]));
        frame.light_dir = .{ d.direction.x, d.direction.y, d.direction.z, 0.0 };
        frame.light_color = .{ d.color.x, d.color.y, d.color.z, d.intensity };
        frame.ambient = .{ d.ambient.x, d.ambient.y, d.ambient.z, 0.0 };
        frame.shadow_params[2] = 1.0;
    }
    var am_segc: usize = 0;
    const am_segs = ctx.?.view.?(ctx, 3, &am_segc);
    if (am_segc != 0 and am_segs[0].count != 0) {
        const al: *const c.ke_ambient_light_component = @ptrCast(@alignCast(am_segs[0].columns[0]));
        frame.ambient = .{ al.color.x, al.color.y, al.color.z, 0.0 };
    }
    core.*.upload.?(core, fwd.frame_uniform, 0, &frame, @sizeOf(PerFrame));

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 4, &segc);
    const draw_count = collectDraws(core, cam, view, segs, segc, fwd.draws[0..MAX_DRAWS]);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_bind_group.?(rp, 0, fwd.frame_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 3, core.*.resource_bind_group.?(core, "cluster_lights"), null, 0);

    var d: u32 = 0;
    while (d < draw_count) : (d += 1) {
        const draw = fwd.draws[d];
        var vbo: c.ke_gpu_buffer = 0;
        var ibo: c.ke_gpu_buffer = 0;
        var idx_count: u32 = 0;
        if (core.*.mesh_buffers.?(core, draw.mesh.mesh, &vbo, &ibo, &idx_count) == 0) continue;

        if (!fwd.resolvePipeline(core.*.material_shader.?(core, draw.mesh.material))) continue;
        rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template));

        const model = zm.loadMat(draw.world.matrix.m[0..]);
        const mvp = zm.mul(model, view_proj);
        var u: PerObject = undefined;
        zm.storeMat(u.mvp[0..], mvp);
        zm.storeMat(u.model[0..], model);
        const offset: u32 = d * UNIFORM_STRIDE;
        core.*.upload.?(core, fwd.obj_uniform, offset, &u, @sizeOf(PerObject));

        const mat_bg = core.*.material_bind_group.?(core, draw.mesh.material);
        rp.*.set_bind_group.?(rp, 1, mat_bg, null, 0);
        rp.*.set_bind_group.?(rp, 2, fwd.obj_bind_group, &offset, 1);
        rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
        rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
        rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

fn setup(fwd: *ForwardModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         render_camera: *c.ke_render_camera, logger: ?*c.ke_logger, ibl_enabled: bool,
         mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id, camera_cid: c.ke_component_id,
         light_cid: c.ke_component_id, ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id,
         frame_cid: c.ke_component_id,
         out_error: [*c][*c]c.ke_error) bool {
    fwd.core = core;
    fwd.device = dev;
    fwd.camera = render_camera;
    fwd.logger = logger;
    fwd.ibl_enabled = ibl_enabled;
    fwd.mesh_cid = mesh_cid;
    fwd.world_transform_cid = world_transform_cid;
    fwd.camera_cid = camera_cid;
    fwd.light_cid = light_cid;
    fwd.ambient_cid = ambient_cid;
    fwd.skybox_cid = skybox_cid;
    fwd.env_cubemap = .{ .bits = c.KE_HANDLE_NONE };

    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 7, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 8, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    fwd.frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 8,
        .entries = &frame_bgl_entries,
    });

    const obj_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0,
        .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .has_dynamic_offset = 1,
        .view_dimension = 0,
    };
    fwd.obj_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &obj_bgl_entry,
    });

    fwd.attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 3 * @sizeOf(f32) },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = 6 * @sizeOf(f32) },
        .{ .shader_location = 3, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 8 * @sizeOf(f32) },
    };
    fwd.vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = 11 * @sizeOf(f32),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 4,
        .attributes = &fwd.attrs,
    };

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.vertex_buffer_count = 1;
    pp.vertex_buffers = &fwd.vbl;
    pp.blend_state.blend_enabled = 1;
    pp.blend_state.src_color = c.KE_GPU_BLEND_FACTOR_SRC_ALPHA;
    pp.blend_state.dst_color = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 1;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS_EQUAL;
    pp.bind_group_layouts[0] = fwd.frame_bgl;
    pp.bind_group_layouts[1] = core.*.material_layout.?(core);
    pp.bind_group_layouts[2] = fwd.obj_bgl;
    pp.bind_group_layouts[3] = core.*.resource_bind_group_layout.?(core, "cluster_lights");
    pp.bind_group_layout_count = 4;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    pp.color_target_count = 1;
    fwd.pipeline_template = pp;

    if (!fwd.resolvePipeline(DEFAULT_MATERIAL_SHADER)) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "transparent-forward: default material shader failed to load", @src().file, @intCast(@src().line), null);
        return false;
    }
    if (core.*.get_or_create_pipeline.?(core, &fwd.pipeline_template) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "transparent-forward: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    fwd.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(PerFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;

    fwd.obj_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = UNIFORM_STRIDE * MAX_DRAWS,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (fwd.obj_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    const obj_bg_entry = c.ke_gpu_bind_group_entry{
        .binding = 0,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = fwd.obj_uniform,
        .buffer_offset = 0,
        .buffer_size = @sizeOf(PerObject),
        .texture_view = 0,
        .sampler = 0,
    };
    fwd.obj_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = fwd.obj_bgl,
        .entry_count = 1,
        .entries = &obj_bg_entry,
    }, out_error);
    if (fwd.obj_bind_group == c.KE_GPU_INVALID_HANDLE) return false;

    const hdr_opaque_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "hdr_opaque",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, out_error);

    rebuildFrameBindGroup(fwd);

    const shadow_map_cid = core.*.cid.?(core, "shadow_map");
    const shadow_enabled = shadow_map_cid != c.KE_COMPONENT_INVALID;
    const cluster_lights_cid = core.*.cid.?(core, "light_clusters");

    fwd.writes = .{ "hdr", "depth" };
    fwd.reads = .{"shadow_map"};
    fwd.io = std.mem.zeroes(c.ke_render_pass_io);
    fwd.io.writes = @ptrCast(&fwd.writes);
    fwd.io.writes_count = 2;
    fwd.io.reads = @ptrCast(&fwd.reads);
    fwd.io.reads_count = if (shadow_enabled) 1 else 0;
    fwd.io.load = 1;
    fwd.io.cmd_slot = 6;

    var ac: u32 = 0;
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, "hdr"), .access = c.KE_ACCESS_WRITE };
    ac += 1;
    fwd.access[ac] = .{ .cid = hdr_opaque_cid, .access = c.KE_ACCESS_WRITE };
    ac += 1;
    fwd.access[ac] = .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = camera_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = light_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = ambient_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    fwd.access[ac] = .{ .cid = cluster_lights_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    if (shadow_enabled) {
        fwd.access[ac] = .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_READ };
        ac += 1;
    }
    fwd.access_count = ac;

    const rd = c.KE_ACCESS_READ;
    fwd.queries = std.mem.zeroes([5]c.ke_query_decl);
    fwd.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    fwd.queries[0].terms[1] = .{ .cid = world_transform_cid, .access = rd };
    fwd.queries[0].term_count = 2;
    fwd.queries[1].terms[0] = .{ .cid = skybox_cid, .access = rd };
    fwd.queries[1].term_count = 1;
    fwd.queries[2].terms[0] = .{ .cid = light_cid, .access = rd };
    fwd.queries[2].term_count = 1;
    fwd.queries[3].terms[0] = .{ .cid = ambient_cid, .access = rd };
    fwd.queries[3].term_count = 1;
    fwd.queries[4].terms[0] = .{ .cid = mesh_cid, .access = rd };
    fwd.queries[4].terms[1] = .{ .cid = world_transform_cid, .access = rd };
    fwd.queries[4].term_count = 2;
    return true;
}

fn destroyModule(fwd: *const ForwardModule) void {
    const dev = fwd.device;
    const invalid = c.KE_GPU_INVALID_HANDLE;
    if (fwd.frame_bind_group != invalid) dev.destroy_bind_group.?(dev, fwd.frame_bind_group);
    if (fwd.obj_bind_group != invalid) dev.destroy_bind_group.?(dev, fwd.obj_bind_group);
    if (fwd.frame_uniform != invalid) dev.destroy_buffer.?(dev, fwd.frame_uniform);
    if (fwd.obj_uniform != invalid) dev.destroy_buffer.?(dev, fwd.obj_uniform);
    if (fwd.frame_bgl != invalid) dev.destroy_bind_group_layout.?(dev, fwd.frame_bgl);
    if (fwd.obj_bgl != invalid) dev.destroy_bind_group_layout.?(dev, fwd.obj_bgl);
}

fn destroyHandle(self: ?*c.ke_render_forward) callconv(.c) void {
    const fwd: *ForwardModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(fwd);
    gpa.destroy(fwd);
}

export fn ke_render_forward_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                    device: ?*c.ke_gpu_device, render_camera: ?*c.ke_render_camera,
                                    logger: ?*c.ke_logger, ibl_enabled: c.ke_bool,
                                    mesh_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                    camera_cid: c.ke_component_id, light_cid: c.ke_component_id,
                                    ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id,
                                    frame_cid: c.ke_component_id,
                                    out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_forward_handle {
    const empty = c.ke_render_forward_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;
    const camera_api = render_camera orelse return empty;

    const fwd = gpa.create(ForwardModule) catch return empty;
    fwd.* = .{};
    if (!setup(fwd, dev, core_ref, camera_api, logger, ibl_enabled != 0,
               mesh_cid, world_transform_cid, camera_cid, light_cid, ambient_cid, skybox_cid, frame_cid, out_error))
    {
        destroyModule(fwd);
        gpa.destroy(fwd);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.forward_transparent";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &fwd.queries;
    params.query_count = fwd.queries.len;
    params.access_list = &fwd.access;
    params.access_count = fwd.access_count;
    params.pinned_thread = 0;
    params.user_data = fwd;
    params.execute = system;
    if (rt.register_system.?(rt, &params, out_error) == 0) {
        destroyModule(fwd);
        gpa.destroy(fwd);
        return empty;
    }

    return .{ .ref = @ptrCast(fwd), .destroy = destroyHandle };
}

const testing = std.testing;

fn blendUnlessZero(_: [*c]c.ke_render_service, m: c.ke_material_handle) callconv(.c) c.ke_alpha_mode {
    return if (m.bits == 0) c.KE_ALPHA_MODE_OPAQUE else c.KE_ALPHA_MODE_BLEND;
}

fn blendingService() c.ke_render_service {
    var svc = std.mem.zeroes(c.ke_render_service);
    svc.material_alpha_mode = blendUnlessZero;
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

fn transformAt(z: f32) c.ke_world_transform_component {
    var wt = std.mem.zeroes(c.ke_world_transform_component);
    wt.matrix.m[14] = z;
    return wt;
}

fn oneSegment(meshes: []const c.ke_mesh_component, wts: []const c.ke_world_transform_component) c.ke_ecs_segment {
    var seg = std.mem.zeroes(c.ke_ecs_segment);
    seg.columns[0] = @constCast(@ptrCast(meshes.ptr));
    seg.columns[1] = @constCast(@ptrCast(wts.ptr));
    seg.count = meshes.len;
    return seg;
}

test "a mesh on a layer the camera's cull_mask omits is not drawn" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 0b001), out[0].mesh.layers);
}

test "a camera whose mask names several layers draws a mesh on any one of them" {
    var svc = blendingService();
    const cam = cameraSeeing(0b101);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 2), n);
}

test "a mesh sharing one bit of a multi layer mask is drawn once, not once per bit" {
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]c.ke_mesh_component{meshOn(0b111)};
    const wts = [_]c.ke_world_transform_component{transformAt(-1)};
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 1), n);
}

test "a camera that names no layer draws nothing, even with meshes in front of it" {
    var svc = blendingService();
    const cam = cameraSeeing(0);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 0), n);
}

test "an opaque mesh the camera can see still stays out of the transparent pass" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    var opaque_mesh = meshOn(0b001);
    opaque_mesh.material = .{ .bits = 0 };
    const meshes = [_]c.ke_mesh_component{ opaque_mesh, meshOn(0b001) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-1), transformAt(-2) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 1), n);
    try testing.expectEqual(@as(u32, 7), out[0].mesh.material.bits);
}

test "the culled draws come back farthest first, so blending composites back to front" {
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-2), transformAt(-9), transformAt(-5) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    const eye_at_origin = zm.lookAtRh(zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 0, -1, 1), zm.f32x4(0, 1, 0, 0));

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, eye_at_origin, &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 3), n);
    try testing.expectEqual(@as(u32, 0b010), out[0].mesh.layers);
    try testing.expectEqual(@as(u32, 0b100), out[1].mesh.layers);
    try testing.expectEqual(@as(u32, 0b001), out[2].mesh.layers);
}

test "draws come back farthest first under a left handed view too" {
    var svc = blendingService();
    const cam = cameraSeeing(0b111);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010), meshOn(0b100) };
    const wts = [_]c.ke_world_transform_component{ transformAt(2), transformAt(9), transformAt(5) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    const eye_at_origin = zm.lookAtLh(zm.f32x4(0, 0, 0, 1), zm.f32x4(0, 0, 1, 1), zm.f32x4(0, 1, 0, 0));

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, eye_at_origin, &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 3), n);
    try testing.expectEqual(@as(u32, 0b010), out[0].mesh.layers);
    try testing.expectEqual(@as(u32, 0b100), out[1].mesh.layers);
    try testing.expectEqual(@as(u32, 0b001), out[2].mesh.layers);
}

test "collection stops at the caller's capacity instead of writing past it" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b001), meshOn(0b001) };
    const wts = [_]c.ke_world_transform_component{ transformAt(-1), transformAt(-2), transformAt(-3) };
    const segs = [_]c.ke_ecs_segment{oneSegment(&meshes, &wts)};

    var out: [2]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 2), n);
}

test "meshes are gathered across every segment the query returned" {
    var svc = blendingService();
    const cam = cameraSeeing(0b001);
    const a_meshes = [_]c.ke_mesh_component{meshOn(0b001)};
    const a_wts = [_]c.ke_world_transform_component{transformAt(-1)};
    const b_meshes = [_]c.ke_mesh_component{ meshOn(0b001), meshOn(0b010) };
    const b_wts = [_]c.ke_world_transform_component{ transformAt(-2), transformAt(-3) };
    const segs = [_]c.ke_ecs_segment{ oneSegment(&a_meshes, &a_wts), oneSegment(&b_meshes, &b_wts) };

    var out: [8]Draw = undefined;
    const n = collectDraws(&svc, &cam, zm.identity(), &segs, segs.len, out[0..]);

    try testing.expectEqual(@as(u32, 2), n);
}

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the forward pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_forward_create(rt.api(), core.api(), dev.api(), &camera, null, 0, 1, 2, 3, 4, 5, 6, 7, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a forward pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_forward_create(rt.api(), core.api(), dev.api(), &camera, null, 0, 1, 2, 3, 4, 5, 6, 7, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a forward pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init();
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var camera = std.mem.zeroes(c.ke_render_camera);
    const h = ke_render_forward_create(rt.api(), core.api(), dev.api(), &camera, null, 0, 1, 2, 3, 4, 5, 6, 7, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
