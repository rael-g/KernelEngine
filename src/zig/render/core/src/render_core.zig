const std = @import("std");

pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu_surface_ext.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
});

const gpa = std.heap.c_allocator;

// Fold the render module factory (ke_render_module_create) into this lib so it
// calls ke_render_core_create in-lib — a separate Zig DLL can't link this one's
// import lib on Windows. Force-referenced so its export fn is emitted.
comptime {
    _ = @import("render_module.zig");
}

const MAX_RESOURCES = 64;
const MAX_CMD_BUFFERS = 64;
const MAX_COLOR_ATTACH = 8;
const MAX_MESHES = 256;
const MAX_TEXTURES = 256;
const MAX_MATERIALS = 256;

const Mesh = struct {
    vbo: c.ke_gpu_buffer,
    ibo: c.ke_gpu_buffer,
    index_count: u32,
};

const Texture = struct {
    tex: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
};

const Material = struct {
    ubo: c.ke_gpu_buffer, // base_color uniform
    bind_group: c.ke_gpu_bind_group, // set 1: base_color + albedo + sampler
};

const Resource = struct {
    name: [*c]const u8,
    cid: c.ke_component_id,
    format: c.ke_gpu_texture_format,
    texture: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
    is_backbuffer: bool,
    is_transient: bool, // owns texture+view → destroyed on core destroy
};

const CoreState = struct {
    device: *c.ke_gpu_device,
    ecs: *c.ke_ecs,
    surface: ?*const c.ke_gpu_surface_ext,
    queue: c.ke_gpu_queue,

    resources: [MAX_RESOURCES]Resource,
    resource_count: u32,

    backbuffer_w: u32,
    backbuffer_h: u32,

    cmd_bufs: [MAX_CMD_BUFFERS][*c]c.ke_gpu_command_buffer,
    cmd_count: u32,

    meshes: [MAX_MESHES]Mesh,
    mesh_count: u32,

    clear_color: [4]f32,

    textures: [MAX_TEXTURES]Texture,
    texture_count: u32,
    materials: [MAX_MATERIALS]Material,
    material_count: u32,
    sampler: c.ke_gpu_sampler, // shared linear-repeat sampler
    material_bgl: c.ke_gpu_bind_group_layout, // set 1 layout
    default_normal: c.ke_texture_handle, // built-in flat (0,0,1) normal map
    default_cubemap: c.ke_texture_handle, // built-in 1×1 black env cubemap

    fn meshAt(self: *CoreState, idx: u32) ?*Mesh {
        if (idx >= self.mesh_count) return null;
        return &self.meshes[idx];
    }

    fn textureAt(self: *CoreState, idx: u32) ?*Texture {
        if (idx >= self.texture_count) return null;
        return &self.textures[idx];
    }

    fn materialAt(self: *CoreState, idx: u32) *Material {
        // Unknown handle falls back to the built-in white material (index 0).
        if (idx >= self.material_count) return &self.materials[0];
        return &self.materials[idx];
    }

    fn find(self: *CoreState, name: [*c]const u8) ?*Resource {
        var i: u32 = 0;
        while (i < self.resource_count) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(self.resources[i].name), std.mem.span(name))) {
                return &self.resources[i];
            }
        }
        return null;
    }
};

const PassState = struct {
    core: *CoreState,
    io: c.ke_render_pass_io,
    encoder: *c.ke_gpu_command_encoder,
};

inline fn coreOf(self: [*c]c.ke_render_core) *CoreState {
    return @alignCast(@ptrCast(self.*.handle));
}
inline fn passOf(self: [*c]c.ke_render_pass_ctx) *PassState {
    return @alignCast(@ptrCast(self.*.handle));
}

fn isDepthFormat(fmt: c.ke_gpu_texture_format) bool {
    return fmt >= c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

// ── ke_render_core slots ────────────────────────────────────────────────────

fn declare(self: [*c]c.ke_render_core, desc: [*c]const c.ke_render_resource_desc, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = coreOf(self);
    if (st.resource_count >= MAX_RESOURCES) return c.KE_COMPONENT_INVALID;

    const cid = st.ecs.component_register.?(st.ecs, desc.*.name, 0);

    var w = desc.*.width;
    var h = desc.*.height;
    if (desc.*.size_mode == c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER) {
        w = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_w)) * desc.*.scale_x);
        h = @intFromFloat(@as(f32, @floatFromInt(st.backbuffer_h)) * desc.*.scale_y);
    }

    const depth = isDepthFormat(desc.*.format);
    const usage: c.ke_gpu_texture_usage = if (depth)
        c.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH
    else
        c.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH | c.KE_GPU_TEXTURE_USAGE_SAMPLED;

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = w,
        .height = h,
        .depth_or_array_layers = 1,
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = usage,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = null,
        .initial_data_size = 0,
    });

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = desc.*.format,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (depth) c.KE_GPU_TEXTURE_ASPECT_DEPTH else c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    st.resources[st.resource_count] = .{
        .name = desc.*.name,
        .cid = cid,
        .format = desc.*.format,
        .texture = tex,
        .view = view,
        .is_backbuffer = false,
        .is_transient = true,
    };
    st.resource_count += 1;
    return cid;
}

fn importTexture(self: [*c]c.ke_render_core, name: [*c]const u8, tex: c.ke_gpu_texture, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    _ = out_error;
    const st = coreOf(self);
    if (st.resource_count >= MAX_RESOURCES) return c.KE_COMPONENT_INVALID;
    const cid = st.ecs.component_register.?(st.ecs, name, 0);
    st.resources[st.resource_count] = .{
        .name = name,
        .cid = cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_INVALID,
        .texture = tex,
        .view = c.KE_GPU_INVALID_HANDLE, // view creation needs a format — refinement
        .is_backbuffer = false,
        .is_transient = false,
    };
    st.resource_count += 1;
    return cid;
}

fn cidOf(self: [*c]c.ke_render_core, name: [*c]const u8) callconv(.c) c.ke_component_id {
    const st = coreOf(self);
    if (st.find(name)) |r| return r.cid;
    return c.KE_COMPONENT_INVALID;
}

fn beginPass(self: [*c]c.ke_render_core, sys: ?*c.ke_system_ctx, io: [*c]const c.ke_render_pass_io) callconv(.c) [*c]c.ke_render_pass_ctx {
    _ = sys;
    const st = coreOf(self);
    const ps = gpa.create(PassState) catch return null;
    ps.* = .{
        .core = st,
        .io = io.*,
        .encoder = st.device.create_command_encoder.?(st.device),
    };
    const ctx = gpa.create(c.ke_render_pass_ctx) catch {
        gpa.destroy(ps);
        return null;
    };
    ctx.* = .{
        .handle = ps,
        .read = ctxRead,
        .write = ctxRead,
        .begin_render = ctxBeginRender,
        .begin_compute = ctxBeginCompute,
        .encoder = ctxEncoder,
        .query_ext = ctxQueryExt,
        .backbuffer_size = ctxBackbufferSize,
    };
    return ctx;
}

fn endPass(self: [*c]c.ke_render_core, ctx: [*c]c.ke_render_pass_ctx) callconv(.c) void {
    const st = coreOf(self);
    const ps = passOf(ctx);
    const cmd = ps.encoder.finish.?(ps.encoder);
    ps.encoder.destroy.?(ps.encoder);
    if (st.cmd_count < MAX_CMD_BUFFERS) {
        st.cmd_bufs[st.cmd_count] = cmd;
        st.cmd_count += 1;
    }
    gpa.destroy(ps);
    gpa.destroy(@as(*c.ke_render_pass_ctx, @ptrCast(ctx)));
}

fn beginFrame(self: [*c]c.ke_render_core, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = coreOf(self);
    st.cmd_count = 0;
    if (st.surface) |surf| {
        surf.current_size.?(surf, &st.backbuffer_w, &st.backbuffer_h);
        const view = surf.acquire_current_texture_view.?(surf);
        if (view == c.KE_GPU_INVALID_HANDLE) return 0;
        if (st.find("backbuffer")) |bb| bb.view = view;
    }
    return 1;
}

fn endFrame(self: [*c]c.ke_render_core, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = coreOf(self);
    if (st.cmd_count > 0) {
        st.device.queue_submit.?(st.device, st.queue, &st.cmd_bufs, st.cmd_count);
        var i: u32 = 0;
        while (i < st.cmd_count) : (i += 1) {
            const cmd = st.cmd_bufs[i];
            cmd.*.destroy.?(cmd);
        }
        st.cmd_count = 0;
    }
    st.device.queue_present.?(st.device, st.queue);
    if (st.find("backbuffer")) |bb| {
        if (bb.view != c.KE_GPU_INVALID_HANDLE) {
            st.device.destroy_texture_view.?(st.device, bb.view);
            bb.view = c.KE_GPU_INVALID_HANDLE;
        }
    }
    return 1;
}

fn uploadMesh(self: [*c]c.ke_render_core, vertices: ?*const anyopaque, vertices_size: usize,
              indices: [*c]const u16, index_count: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_mesh_handle {
    _ = out_error;
    const st = coreOf(self);
    if (st.mesh_count >= MAX_MESHES) return .{ .idx = c.KE_HANDLE_NONE };

    const vbo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = vertices,
        .size = vertices_size,
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    if (vbo == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const ibo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = @ptrCast(indices),
        .size = index_count * @sizeOf(u16),
        .usage = c.KE_GPU_BUFFER_USAGE_INDEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    if (ibo == c.KE_GPU_INVALID_HANDLE) {
        st.device.destroy_buffer.?(st.device, vbo);
        return .{ .idx = c.KE_HANDLE_NONE };
    }

    const idx = st.mesh_count;
    st.meshes[idx] = .{ .vbo = vbo, .ibo = ibo, .index_count = index_count };
    st.mesh_count += 1;
    return .{ .idx = idx };
}

fn meshBuffers(self: [*c]c.ke_render_core, h: c.ke_mesh_handle, out_vbo: [*c]c.ke_gpu_buffer,
               out_ibo: [*c]c.ke_gpu_buffer, out_index_count: [*c]u32) callconv(.c) c.ke_bool {
    const st = coreOf(self);
    const m = st.meshAt(h.idx) orelse return 0;
    out_vbo.* = m.vbo;
    out_ibo.* = m.ibo;
    out_index_count.* = m.index_count;
    return 1;
}

fn setClearColor(self: [*c]c.ke_render_core, r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    coreOf(self).clear_color = .{ r, g, b, a };
}

fn uploadTexture(self: [*c]c.ke_render_core, width: u32, height: u32,
                 rgba: ?*const anyopaque, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    _ = out_error;
    const st = coreOf(self);
    if (st.texture_count >= MAX_TEXTURES) return .{ .idx = c.KE_HANDLE_NONE };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = width,
        .height = height,
        .depth_or_array_layers = 1,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .usage = c.KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = rgba,
        .initial_data_size = width * height * 4,
    });
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_2D,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 1,
    });

    const idx = st.texture_count;
    st.textures[idx] = .{ .tex = tex, .view = view };
    st.texture_count += 1;
    return .{ .idx = idx };
}

fn createMaterial(self: [*c]c.ke_render_core, base_color: [*c]const f32,
                  metallic: f32, roughness: f32, albedo: c.ke_texture_handle,
                  normal: c.ke_texture_handle, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_material_handle {
    _ = out_error;
    const st = coreOf(self);
    if (st.material_count >= MAX_MATERIALS) return .{ .idx = c.KE_HANDLE_NONE };

    // std140: float4 base_color + (metallic, roughness) packed into the next slot.
    const mat_data = [8]f32{
        base_color[0], base_color[1], base_color[2], base_color[3],
        metallic,      roughness,     0.0,           0.0,
    };
    const ubo = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .initial_data = &mat_data,
        .size = 32,
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });

    // Unknown / none albedo resolves to the built-in white texture (index 0);
    // none normal resolves to the built-in flat (0,0,1) normal map.
    const alb_idx = if (albedo.idx == c.KE_HANDLE_NONE) 0 else albedo.idx;
    const alb_view = (st.textureAt(alb_idx) orelse &st.textures[0]).view;
    const nrm_idx = if (normal.idx == c.KE_HANDLE_NONE) st.default_normal.idx else normal.idx;
    const nrm_view = (st.textureAt(nrm_idx) orelse &st.textures[st.default_normal.idx]).view;

    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .buffer = ubo, .buffer_offset = 0, .buffer_size = 32, .texture_view = 0, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = alb_view, .sampler = 0 },
        .{ .binding = 2, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = st.sampler },
        .{ .binding = 3, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = nrm_view, .sampler = 0 },
    };
    const bg = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .layout = st.material_bgl,
        .entry_count = 4,
        .entries = &entries,
    });

    const idx = st.material_count;
    st.materials[idx] = .{ .ubo = ubo, .bind_group = bg };
    st.material_count += 1;
    return .{ .idx = idx };
}

fn materialLayout(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_bind_group_layout {
    return coreOf(self).material_bgl;
}

fn materialBindGroup(self: [*c]c.ke_render_core, h: c.ke_material_handle) callconv(.c) c.ke_gpu_bind_group {
    return coreOf(self).materialAt(h.idx).bind_group;
}

fn uploadCubemap(self: [*c]c.ke_render_core, face_size: u32, faces: ?*const anyopaque,
                 out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_texture_handle {
    _ = out_error;
    const st = coreOf(self);
    if (st.texture_count >= MAX_TEXTURES) return .{ .idx = c.KE_HANDLE_NONE };

    const tex = st.device.create_texture.?(st.device, &c.ke_gpu_texture_params{
        .width = face_size,
        .height = face_size,
        .depth_or_array_layers = 6,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_CUBE,
        .usage = c.KE_GPU_TEXTURE_USAGE_SAMPLED,
        .mip_level_count = 1,
        .sample_count = 1,
        .initial_data = faces,
        .initial_data_size = face_size * face_size * 4 * 6,
    });
    if (tex == c.KE_GPU_INVALID_HANDLE) return .{ .idx = c.KE_HANDLE_NONE };

    const view = st.device.create_texture_view.?(st.device, tex, &c.ke_gpu_texture_view_params{
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM,
        .dimension = c.KE_GPU_TEXTURE_DIM_CUBE,
        .aspect = c.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = 0,
        .mip_level_count = 1,
        .base_array_layer = 0,
        .array_layer_count = 6,
    });

    const idx = st.texture_count;
    st.textures[idx] = .{ .tex = tex, .view = view };
    st.texture_count += 1;
    return .{ .idx = idx };
}

fn textureView(self: [*c]c.ke_render_core, h: c.ke_texture_handle) callconv(.c) c.ke_gpu_texture_view {
    const st = coreOf(self);
    // texture_view is used to bind the environment cubemap; an unset/none handle
    // resolves to the built-in default (black) cubemap so the binding stays valid.
    const idx = if (h.idx == c.KE_HANDLE_NONE) st.default_cubemap.idx else h.idx;
    return (st.textureAt(idx) orelse &st.textures[st.default_cubemap.idx]).view;
}

fn samplerOf(self: [*c]c.ke_render_core) callconv(.c) c.ke_gpu_sampler {
    return coreOf(self).sampler;
}

// ── ke_render_pass_ctx slots ────────────────────────────────────────────────

fn ctxRead(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const ps = passOf(self);
    if (ps.core.find(name)) |r| return r.view;
    return c.KE_GPU_INVALID_HANDLE;
}

fn ctxBeginRender(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_render_pass {
    const ps = passOf(self);
    var colors: [MAX_COLOR_ATTACH]c.ke_gpu_color_attachment = undefined;
    var color_count: u32 = 0;
    var depth: c.ke_gpu_depth_stencil_attachment = undefined;
    var has_depth = false;

    var i: u32 = 0;
    while (i < ps.io.writes_count) : (i += 1) {
        const r = ps.core.find(ps.io.writes[i]) orelse continue;
        if (isDepthFormat(r.format)) {
            depth = .{
                .view = r.view,
                .depth_load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .depth_store_op = c.KE_GPU_STORE_OP_STORE,
                .stencil_store_op = c.KE_GPU_STORE_OP_DONT_CARE,
                .clear_depth = 1.0,
                .clear_stencil = 0,
                .depth_read_only = 0,
                .stencil_read_only = 0,
            };
            has_depth = true;
        } else if (color_count < MAX_COLOR_ATTACH) {
            colors[color_count] = .{
                .view = r.view,
                .load_op = c.KE_GPU_LOAD_OP_CLEAR,
                .store_op = c.KE_GPU_STORE_OP_STORE,
                .clear_value = .{ .color = ps.core.clear_color },
            };
            color_count += 1;
        }
    }

    const params = c.ke_gpu_render_pass_params{
        .color_attachments = &colors,
        .color_attachment_count = color_count,
        .depth_stencil_attachment = if (has_depth) &depth else null,
    };
    return ps.encoder.begin_render_pass.?(ps.encoder, &params);
}

fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = passOf(self);
    return ps.encoder.begin_compute_pass.?(ps.encoder);
}

fn ctxEncoder(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_command_encoder {
    return passOf(self).encoder;
}

fn ctxQueryExt(self: [*c]c.ke_render_pass_ctx, name: [*c]const u8) callconv(.c) ?*const anyopaque {
    const ps = passOf(self);
    return ps.core.device.query_extension.?(ps.core.device, name);
}

fn ctxBackbufferSize(self: [*c]c.ke_render_pass_ctx, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
    const ps = passOf(self);
    if (out_w != null) out_w.* = ps.core.backbuffer_w;
    if (out_h != null) out_h.* = ps.core.backbuffer_h;
}

// ── Factory + destroy ───────────────────────────────────────────────────────

fn destroyCore(self: [*c]c.ke_render_core) callconv(.c) void {
    const st = coreOf(self);
    var i: u32 = 0;
    while (i < st.resource_count) : (i += 1) {
        const r = &st.resources[i];
        if (r.is_transient) {
            if (r.view != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
            if (r.texture != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        }
    }
    var m: u32 = 0;
    while (m < st.mesh_count) : (m += 1) {
        st.device.destroy_buffer.?(st.device, st.meshes[m].vbo);
        st.device.destroy_buffer.?(st.device, st.meshes[m].ibo);
    }
    var t: u32 = 0;
    while (t < st.texture_count) : (t += 1) {
        st.device.destroy_texture_view.?(st.device, st.textures[t].view);
        st.device.destroy_texture.?(st.device, st.textures[t].tex);
    }
    var mat: u32 = 0;
    while (mat < st.material_count) : (mat += 1) {
        st.device.destroy_buffer.?(st.device, st.materials[mat].ubo);
    }
    if (st.sampler != c.KE_GPU_INVALID_HANDLE) st.device.destroy_sampler.?(st.device, st.sampler);
    gpa.destroy(st);
    gpa.destroy(@as(*c.ke_render_core, @ptrCast(self)));
}

export fn ke_render_core_create(device: ?*c.ke_gpu_device, ecs: ?*c.ke_ecs, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_core_handle {
    _ = out_error;
    const dev = device orelse return .{ .ref = null, .destroy = null };
    const e = ecs orelse return .{ .ref = null, .destroy = null };

    const st = gpa.create(CoreState) catch return .{ .ref = null, .destroy = null };
    const surf_raw = dev.query_extension.?(dev, c.KE_GPU_SURFACE_EXT_NAME);
    const surf: ?*const c.ke_gpu_surface_ext = if (surf_raw) |p| @ptrCast(@alignCast(p)) else null;
    var bb_w: u32 = 0;
    var bb_h: u32 = 0;
    if (surf) |s| s.current_size.?(s, &bb_w, &bb_h);
    st.* = .{
        .device = dev,
        .ecs = e,
        .surface = surf,
        .queue = dev.get_default_queue.?(dev),
        .resources = undefined,
        .resource_count = 0,
        .backbuffer_w = bb_w,
        .backbuffer_h = bb_h,
        .cmd_bufs = undefined,
        .cmd_count = 0,
        .meshes = undefined,
        .mesh_count = 0,
        .clear_color = .{ 0.10, 0.15, 0.30, 1.0 },
        .textures = undefined,
        .texture_count = 0,
        .materials = undefined,
        .material_count = 0,
        .sampler = c.KE_GPU_INVALID_HANDLE,
        .material_bgl = c.KE_GPU_INVALID_HANDLE,
        .default_normal = .{ .idx = c.KE_HANDLE_NONE },
        .default_cubemap = .{ .idx = c.KE_HANDLE_NONE },
    };

    // Built-in backbuffer resource (its view is refreshed each begin_frame).
    const bb_cid = e.component_register.?(e, "backbuffer", 0);
    st.resources[0] = .{
        .name = "backbuffer",
        .cid = bb_cid,
        .format = c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM,
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = true,
        .is_transient = false,
    };
    st.resource_count = 1;

    const core = gpa.create(c.ke_render_core) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    core.* = .{
        .handle = st,
        .declare = declare,
        .import_texture = importTexture,
        .cid = cidOf,
        .begin_pass = beginPass,
        .end_pass = endPass,
        .begin_frame = beginFrame,
        .end_frame = endFrame,
        .upload_mesh = uploadMesh,
        .mesh_buffers = meshBuffers,
        .set_clear_color = setClearColor,
        .upload_texture = uploadTexture,
        .create_material = createMaterial,
        .material_layout = materialLayout,
        .material_bind_group = materialBindGroup,
        .upload_cubemap = uploadCubemap,
        .texture_view = textureView,
        .sampler = samplerOf,
    };

    // Material system: shared sampler + set-1 layout + built-in white texture (0)
    // and white material (0) so untextured/unmaterialed draws still resolve.
    st.sampler = dev.create_sampler.?(dev, &c.ke_gpu_sampler_params{
        .min_filter = c.KE_GPU_FILTER_LINEAR,
        .mag_filter = c.KE_GPU_FILTER_LINEAR,
        .mipmap_filter = c.KE_GPU_SAMPLER_MIPMAP_NEAREST,
        .address_mode_u = c.KE_GPU_ADDRESS_MODE_REPEAT,
        .address_mode_v = c.KE_GPU_ADDRESS_MODE_REPEAT,
        .address_mode_w = c.KE_GPU_ADDRESS_MODE_REPEAT,
        .lod_min_clamp = 0.0,
        .lod_max_clamp = 1.0,
        .compare = c.KE_GPU_COMPARE_UNDEFINED,
        .max_anisotropy = 1,
    });
    const mat_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 2, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
        .{ .binding = 3, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    st.material_bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 4,
        .entries = &mat_bgl_entries,
    });
    const white_px = [_]u8{ 255, 255, 255, 255 };
    _ = uploadTexture(core, 1, 1, &white_px, null); // texture 0 = white albedo
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 }; // (0,0,1) in tangent space
    st.default_normal = uploadTexture(core, 1, 1, &flat_normal_px, null);
    const black_cube_px = [_]u8{0} ** (4 * 6); // 1×1 black on all 6 faces
    st.default_cubemap = uploadCubemap(core, 1, &black_cube_px, null);
    const white_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    _ = createMaterial(core, &white_color, 0.0, 0.5, .{ .idx = c.KE_HANDLE_NONE }, .{ .idx = c.KE_HANDLE_NONE }, null);

    return .{ .ref = core, .destroy = destroyCore };
}
