const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;

const DeferredFrame = extern struct {
    camera_pos: [4]f32,
    light_dir: [4]f32,
    light_color: [4]f32,
    ambient: [4]f32,
    shadow_params: [4]f32,
    viewport: [4]f32,
    view: [16]f32,
    inv_view_proj: [16]f32,
};

const DeferredLightingModule = struct {
    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    camera: *c.ke_render_camera = undefined,
    logger: ?*c.ke_logger = null,
    ibl_enabled: bool = true,

    camera_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    ambient_cid: c.ke_component_id = undefined,
    skybox_cid: c.ke_component_id = undefined,

    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    frame_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    gbuf_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    empty_bgl: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
    empty_bg: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    frame_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    frame_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    gbuf_bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    env_cubemap: c.ke_texture_handle = .{ .bits = c.KE_HANDLE_NONE },

    reads: [6][*c]const u8 = undefined,
    writes: [1][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [13]c.ke_component_access = undefined,
    queries: [4]c.ke_query_decl = undefined,
    access_count: u32 = 0,
};

fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_deferred_lighting", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

inline fn moduleOf(user: ?*anyopaque) *DeferredLightingModule {
    return @alignCast(@ptrCast(user.?));
}

fn rebuildFrameBindGroup(dl: *DeferredLightingModule) void {
    const dev = dl.device;
    const core = dl.core;
    const env_view = core.*.texture_view.?(core, dl.env_cubemap);
    const white_view = core.*.texture_view.?(core, core.*.white_texture.?(core));
    const black_cube_view = core.*.texture_view.?(core, .{ .bits = c.KE_HANDLE_NONE });
    const smp = core.*.sampler.?(core);

    const shadow_view_raw = core.*.resource_view.?(core, "shadow_map");
    const shadow_tex_view = if (shadow_view_raw != c.KE_GPU_INVALID_HANDLE) shadow_view_raw else white_view;
    const shadow_lvp_buf = core.*.resource_buffer.?(core, "shadow_lvp");
    const shadow_lvp_size = core.*.resource_buffer_size.?(core, "shadow_lvp");
    const ibl_view = if (dl.ibl_enabled) env_view else black_cube_view;

    const entries = [6]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = dl.frame_uniform, .buffer_offset = 0, .buffer_size = @sizeOf(DeferredFrame), .texture_view = 0, .sampler = 0 },
        .{ .binding = 4, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = shadow_lvp_buf, .buffer_offset = 0, .buffer_size = shadow_lvp_size, .texture_view = 0, .sampler = 0 },
        .{ .binding = 5, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = shadow_tex_view, .sampler = 0 },
        .{ .binding = 6, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
        .{ .binding = 7, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = ibl_view, .sampler = 0 },
        .{ .binding = 8, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = smp },
    };
    var err: ?*c.ke_error = null;
    dl.frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.frame_bgl,
        .entry_count = 6,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(dl.logger, err, "deferred frame bind group");
}

fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const dl = moduleOf(user);
    const core = dl.core;
    const dev = dl.device;

    var cam_segc: usize = 0;
    const cam_segs = ctx.?.view.?(ctx, 0, &cam_segc);

    const pc = core.*.begin_pass.?(core, ctx, &dl.io);
    if (pc == null) return true;
    if (cam_segc == 0 or cam_segs[0].count == 0) {
        const rp0 = pc.*.begin_render.?(pc);
        rp0.*.end.?(rp0);
        core.*.end_pass.?(core, pc);
        return true;
    }
    const cam: *const c.ke_camera_component = @ptrCast(@alignCast(cam_segs[0].columns[0]));
    const cam_wt: *const c.ke_world_transform_component = @ptrCast(@alignCast(cam_segs[0].columns[1]));

    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    const aspect = if (bh != 0) @as(f32, @floatFromInt(bw)) / @as(f32, @floatFromInt(bh)) else 1.0;

    var view_m: c.ke_mat4 = undefined;
    dl.camera.view.?(dl.camera, &cam_wt.matrix, &view_m);
    var proj_m: c.ke_mat4 = undefined;
    dl.camera.projection.?(dl.camera, cam, aspect, &proj_m);
    const view = zm.loadMat(&view_m.m);
    const view_proj = zm.mul(view, zm.loadMat(&proj_m.m));
    const inv_vp = zm.inverse(view_proj);

    var sky_segc: usize = 0;
    const sky_segs = ctx.?.view.?(ctx, 1, &sky_segc);
    const want_env: c.ke_texture_handle = if (sky_segc != 0 and sky_segs[0].count != 0)
        (@as(*const c.ke_skybox_component, @ptrCast(@alignCast(sky_segs[0].columns[0])))).cubemap
    else
        .{ .bits = c.KE_HANDLE_NONE };
    if (want_env.bits != dl.env_cubemap.bits) {
        dl.env_cubemap = want_env;
        rebuildFrameBindGroup(dl);
    }

    var frame: DeferredFrame = .{
        .camera_pos = .{ cam_wt.matrix.m[12], cam_wt.matrix.m[13], cam_wt.matrix.m[14], 1.0 },
        .light_dir = .{ 0.0, 0.0, 0.0, 0.0 },
        .light_color = .{ 0.0, 0.0, 0.0, 0.0 },
        .ambient = .{ 0.0, 0.0, 0.0, 0.0 },
        .shadow_params = .{ 0.0, 0.0, 0.0, 0.0 },
        .viewport = .{ @floatFromInt(bw), @floatFromInt(bh), 0.0, 0.0 },
        .view = undefined,
        .inv_view_proj = undefined,
    };
    zm.storeMat(frame.view[0..], view);
    zm.storeMat(frame.inv_view_proj[0..], inv_vp);

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
    core.*.upload.?(core, dl.frame_uniform, 0, &frame, @sizeOf(DeferredFrame));

    const albedo_view = pc.*.read.?(pc, "gbuffer_albedo");
    const normal_view = pc.*.read.?(pc, "gbuffer_normal");
    const emissive_view = pc.*.read.?(pc, "gbuffer_emissive");
    const depth_view = pc.*.read.?(pc, "depth");
    const gbuf_entries = [4]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = albedo_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = normal_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = emissive_view, .sampler = 0 },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = depth_view, .sampler = 0 },
    };
    if (dl.gbuf_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, dl.gbuf_bind_group);
    var err: ?*c.ke_error = null;
    dl.gbuf_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.gbuf_bgl,
        .entry_count = 4,
        .entries = &gbuf_entries,
    }, &err);
    if (dl.gbuf_bind_group == c.KE_GPU_INVALID_HANDLE) {
        logGpuError(dl.logger, err, "deferred gbuffer bind group");
        core.*.end_pass.?(core, pc);
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "deferred lighting pass: gbuffer bind group creation failed", @src().file, @intCast(@src().line), err);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &dl.pipeline_params));
    rp.*.set_bind_group.?(rp, 0, dl.frame_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 1, dl.gbuf_bind_group, null, 0);
    rp.*.set_bind_group.?(rp, 2, dl.empty_bg, null, 0);
    rp.*.set_bind_group.?(rp, 3, core.*.resource_bind_group.?(core, "cluster_lights"), null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0);
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

fn setup(dl: *DeferredLightingModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         render_camera: *c.ke_render_camera, logger: ?*c.ke_logger, ibl_enabled: bool,
         camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
         ambient_cid: c.ke_component_id, skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
         out_error: [*c][*c]c.ke_error) bool {
    dl.core = core;
    dl.device = dev;
    dl.camera = render_camera;
    dl.logger = logger;
    dl.ibl_enabled = ibl_enabled;
    dl.camera_cid = camera_cid;
    dl.world_transform_cid = world_transform_cid;
    dl.light_cid = light_cid;
    dl.ambient_cid = ambient_cid;
    dl.skybox_cid = skybox_cid;
    dl.env_cubemap = .{ .bits = c.KE_HANDLE_NONE };

    const frag = c.KE_GPU_SHADER_STAGE_FRAGMENT;
    const frame_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 4, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 5, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 6, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 7, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE },
        .{ .binding = 8, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    dl.frame_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 6,
        .entries = &frame_bgl_entries,
    });

    const gbuf_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = frag, .type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    dl.gbuf_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &gbuf_bgl_entries,
    });

    dl.empty_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 0,
        .entries = null,
    });
    dl.empty_bg = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = dl.empty_bgl,
        .entry_count = 0,
        .entries = null,
    }, out_error);
    if (dl.empty_bg == c.KE_GPU_INVALID_HANDLE) return false;

    const vs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (vs == c.KE_GPU_INVALID_HANDLE) return false;
    const fs = core.*.load_shader.?(core, "deferred_lighting", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (fs == c.KE_GPU_INVALID_HANDLE) return false;

    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module = vs;
    pp.fragment_module = fs;
    pp.vertex_entry = "vs_main";
    pp.fragment_entry = "fs_main";
    pp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    pp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    pp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    pp.bind_group_layouts[0] = dl.frame_bgl;
    pp.bind_group_layouts[1] = dl.gbuf_bgl;
    pp.bind_group_layouts[2] = dl.empty_bgl;
    pp.bind_group_layouts[3] = core.*.resource_bind_group_layout.?(core, "cluster_lights");
    pp.bind_group_layout_count = 4;
    pp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    pp.color_target_count = 1;
    dl.pipeline_params = pp;
    if (core.*.get_or_create_pipeline.?(core, &dl.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "deferred lighting: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    dl.frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = @sizeOf(DeferredFrame),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (dl.frame_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    rebuildFrameBindGroup(dl);

    const hdr_cid = core.*.declare.?(core, &c.ke_render_resource_desc{
        .name = "hdr",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER,
        .width = 0, .height = 0, .scale_x = 1.0, .scale_y = 1.0,
    }, null);

    const shadow_map_cid = core.*.cid.?(core, "shadow_map");
    const shadow_enabled = shadow_map_cid != c.KE_COMPONENT_INVALID;
    const cluster_lights_cid = core.*.cid.?(core, "light_clusters");

    dl.writes = .{"hdr"};
    dl.reads = .{ "gbuffer_albedo", "gbuffer_normal", "gbuffer_emissive", "depth", "shadow_map", "light_clusters" };
    dl.io = std.mem.zeroes(c.ke_render_pass_io);
    dl.io.writes = @ptrCast(&dl.writes);
    dl.io.writes_count = 1;
    dl.io.reads = @ptrCast(&dl.reads);
    dl.io.reads_count = if (shadow_enabled) 6 else 5;
    dl.io.cmd_slot = 4;

    var ac: u32 = 0;
    dl.access[ac] = .{ .cid = hdr_cid, .access = c.KE_ACCESS_WRITE };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_albedo"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_normal"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "gbuffer_emissive"), .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = core.*.cid.?(core, "depth"), .access = c.KE_ACCESS_READ };
    ac += 1;
    if (shadow_enabled) {
        dl.access[ac] = .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_READ };
        ac += 1;
    }
    dl.access[ac] = .{ .cid = cluster_lights_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = camera_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = light_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = ambient_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = skybox_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access[ac] = .{ .cid = frame_cid, .access = c.KE_ACCESS_READ };
    ac += 1;
    dl.access_count = ac;

    const rd = c.KE_ACCESS_READ;
    dl.queries = std.mem.zeroes([4]c.ke_query_decl);
    dl.queries[0].terms[0] = .{ .cid = camera_cid, .access = rd };
    dl.queries[0].terms[1] = .{ .cid = world_transform_cid, .access = rd };
    dl.queries[0].term_count = 2;
    dl.queries[1].terms[0] = .{ .cid = skybox_cid, .access = rd };
    dl.queries[1].term_count = 1;
    dl.queries[2].terms[0] = .{ .cid = light_cid, .access = rd };
    dl.queries[2].term_count = 1;
    dl.queries[3].terms[0] = .{ .cid = ambient_cid, .access = rd };
    dl.queries[3].term_count = 1;
    return true;
}

fn destroyHandle(self: ?*c.ke_render_deferred_lighting) callconv(.c) void {
    const dl: *DeferredLightingModule = @ptrCast(@alignCast(self orelse return));
    const dev = dl.device;
    if (dl.gbuf_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, dl.gbuf_bind_group);
    gpa.destroy(dl);
    heap.release();
}

export fn ke_render_deferred_lighting_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                              device: ?*c.ke_gpu_device, render_camera: ?*c.ke_render_camera,
                                              logger: ?*c.ke_logger, ibl_enabled: c.ke_bool,
                                              camera_cid: c.ke_component_id, world_transform_cid: c.ke_component_id,
                                              light_cid: c.ke_component_id, ambient_cid: c.ke_component_id,
                                              skybox_cid: c.ke_component_id, frame_cid: c.ke_component_id,
                                              out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_deferred_lighting_handle {
    const empty = c.ke_render_deferred_lighting_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;
    const camera_api = render_camera orelse return empty;

    const dl = gpa.create(DeferredLightingModule) catch return empty;
    dl.* = .{};
    if (!setup(dl, dev, core_ref, camera_api, logger, ibl_enabled != 0,
               camera_cid, world_transform_cid, light_cid, ambient_cid, skybox_cid, frame_cid, out_error))
    {
        gpa.destroy(dl);
        return empty;
    }

    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = "render.deferred_lighting";
    params.phase = c.KE_PHASE_RENDER;
    params.queries = &dl.queries;
    params.query_count = dl.queries.len;
    params.access_list = &dl.access;
    params.access_count = dl.access_count;
    params.pinned_thread = 0;
    params.user_data = dl;
    params.execute = system;
    _ = rt.register_system.?(rt, &params, null);

    heap.retain();
    return .{ .ref = @ptrCast(dl), .destroy = destroyHandle };
}
