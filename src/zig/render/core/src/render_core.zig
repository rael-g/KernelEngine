const std = @import("std");

pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/render/gpu_device.h");
    @cInclude("kernel_engine/render/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu_surface_ext.h");
    @cInclude("kernel_engine/render/core/render_core.h");
    @cInclude("kernel_engine/render/core/pass_context.h");
});

pub const gpa = std.heap.c_allocator;

// Fold the render module factory (ke_render_module_create) into this lib so it
// calls ke_render_core_create in-lib — a separate Zig DLL can't link this one's
// import lib on Windows. Force-referenced so its export fn is emitted.
comptime {
    _ = @import("render_module.zig");
}

// This file holds only the shared state (CoreState + its small accessor
// methods), the factory/destroy pair, and the vtable wiring. Each vtable
// slot's actual logic lives in its own file, grouped by concern rather than
// by "everything the core does":
//   resource_table.zig   — named-resource declare/import/lookup (§7 tags)
//   pass_recording.zig    — ke_render_pass_ctx + the compute-pass proxy
//   frame_lifecycle.zig   — begin/end_frame + the deferred-upload recorder
//   asset_upload.zig      — mesh/texture/cubemap/material upload
// The UI overlay used to live here too (a quad-batch pipeline baked into this
// "dumb" core's vtable) — moved out to ui_module.zig on the render_module.zig
// side, as its own opt-in pass alongside tonemap/forward/shadow, since it is a
// rendering feature, not core machinery. ke_render_module_ui_quad is the new
// ABI entry game code calls (see render_module.zig).
const resource_table = @import("resource_table.zig");
const pass_recording = @import("pass_recording.zig");
const frame_lifecycle = @import("frame_lifecycle.zig");
const asset_upload = @import("asset_upload.zig");

pub const MAX_RESOURCES = 64;
pub const MAX_CMD_BUFFERS = 64;
pub const NUM_PRECREATED_ENCODERS = 8; // command encoders pre-created per frame (≥ pass count)
pub const MAX_COLOR_ATTACH = 8;
pub const MAX_MESHES = 256;
pub const MAX_TEXTURES = 256;
pub const MAX_MATERIALS = 256;
pub const MAX_UPLOADS = 4096; // deferred buffer uploads per frame
const UPLOAD_ARENA_SIZE = 8 * 1024 * 1024; // per-frame staging for upload data copies

// A deferred buffer upload. wgpuQueueWriteBuffer is NOT safe to call concurrently
// with render-pass recording on wgpu-native (it deadlocks), so `upload` records
// here lock-free from any pass thread and end_frame replays the writes single-
// threaded before the submit (queue-ordered, so the data lands before the draws).
pub const UploadRecord = struct {
    buffer: c.ke_gpu_buffer,
    gpu_offset: u64,
    arena_offset: usize,
    size: usize,
};

pub const Mesh = struct {
    vbo: c.ke_gpu_buffer,
    ibo: c.ke_gpu_buffer,
    index_count: u32,
};

pub const Texture = struct {
    tex: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
};

pub const Material = struct {
    ubo: c.ke_gpu_buffer, // base_color uniform
    bind_group: c.ke_gpu_bind_group, // set 1: base_color + albedo + sampler
};

pub const Resource = struct {
    name: [*c]const u8,
    cid: c.ke_component_id,
    format: c.ke_gpu_texture_format,
    texture: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
    is_backbuffer: bool,
    is_transient: bool, // owns texture+view → destroyed on core destroy
    // Per-resource clear color. [3]==0 (default) defers to core's global clear_color.
    clear_value: [4]f32,
};

// Accumulated compute-pass recording. On wgpu-native, recording a compute pass
// concurrently with a render pass deadlocks; render-pass recording across distinct
// encoders is safe. So begin_compute hands back a recording proxy that appends the
// commands to one of these (pure CPU writes, safe on any pass thread); end_frame
// replays them into a real compute pass single-threaded. The pass author calls the
// same ke_gpu_compute_pass interface and never sees the difference.
pub const MAX_COMPUTE_CMDS = 32;
pub const ComputeCmd = union(enum) {
    set_pipeline: c.ke_gpu_pipeline,
    set_bind_group: struct { index: u32, bg: c.ke_gpu_bind_group, offsets: [4]u32, count: u32 },
    dispatch: struct { x: u32, y: u32, z: u32 },
    dispatch_indirect: struct { buf: c.ke_gpu_buffer, offset: usize },
};
pub const ComputeRecord = struct {
    pass: c.ke_gpu_compute_pass, // synthesized object handed to the pass body
    cmds: [MAX_COMPUTE_CMDS]ComputeCmd,
    count: u32,
    valid: bool, // a compute pass recorded into this slot this frame
};

pub const CoreState = struct {
    device: *c.ke_gpu_device,
    ecs: *c.ke_ecs,
    surface: ?*const c.ke_gpu_surface_ext,
    queue: c.ke_gpu_queue,

    resources: [MAX_RESOURCES]Resource,
    resource_count: u32,

    backbuffer_w: u32,
    backbuffer_h: u32,

    // Per-pass slots: each pass records into its own encoder (parallel-safe) and
    // parks it here by io.cmd_slot. end_frame FINISHES them single-threaded (the
    // device's command-buffer registry is not thread-safe) and submits in order.
    cmd_encoders: [MAX_CMD_BUFFERS][*c]c.ke_gpu_command_encoder,
    cmd_valid: [MAX_CMD_BUFFERS]bool, // a render pass parked a recorded encoder here

    // Per-slot accumulated compute recording (replayed single-threaded in end_frame).
    compute_records: [MAX_CMD_BUFFERS]ComputeRecord,

    // Deferred uploads — parallel passes record here lock-free (atomic-bumped index
    // + arena offset); end_frame flushes them single-threaded before submit, so the
    // non-thread-safe GPU queue is never written concurrently with pass recording.
    upload_records: [MAX_UPLOADS]UploadRecord,
    upload_count: std.atomic.Value(u32),
    upload_arena: []u8,
    upload_arena_offset: std.atomic.Value(usize),

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
    white_texture: c.ke_texture_handle, // built-in 1×1 white — solid-color UI quads sample this

    ndc: c.ke_ndc_convention, // backend clip-space convention (queried at setup)

    pub fn meshAt(self: *CoreState, idx: u32) ?*Mesh {
        if (idx >= self.mesh_count) return null;
        return &self.meshes[idx];
    }

    pub fn textureAt(self: *CoreState, idx: u32) ?*Texture {
        if (idx >= self.texture_count) return null;
        return &self.textures[idx];
    }

    pub fn materialAt(self: *CoreState, idx: u32) *Material {
        // Unknown handle falls back to the built-in white material (index 0).
        if (idx >= self.material_count) return &self.materials[0];
        return &self.materials[idx];
    }

    pub fn find(self: *CoreState, name: [*c]const u8) ?*Resource {
        var i: u32 = 0;
        while (i < self.resource_count) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(self.resources[i].name), std.mem.span(name))) {
                return &self.resources[i];
            }
        }
        return null;
    }
};

pub const PassState = struct {
    core: *CoreState,
    io: c.ke_render_pass_io,
    encoder: *c.ke_gpu_command_encoder,
    is_compute: bool, // set when begin_compute was called → recording was accumulated
};

pub inline fn coreOf(self: [*c]c.ke_render_core) *CoreState {
    return @alignCast(@ptrCast(self.*.handle));
}
pub inline fn passOf(self: [*c]c.ke_render_pass_ctx) *PassState {
    return @alignCast(@ptrCast(self.*.handle));
}

pub fn isDepthFormat(fmt: c.ke_gpu_texture_format) bool {
    return fmt >= c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
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
    gpa.free(st.upload_arena);
    gpa.destroy(st);
    gpa.destroy(@as(*c.ke_render_core, @ptrCast(self)));
}

export fn ke_render_core_create(device: ?*c.ke_gpu_device, ecs: ?*c.ke_ecs, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_core_handle {
    _ = out_error; // no longer consumed directly here — UI setup (its only caller) moved to ui_module.zig
    const dev = device orelse return .{ .ref = null, .destroy = null };
    const e = ecs orelse return .{ .ref = null, .destroy = null };

    const st = gpa.create(CoreState) catch return .{ .ref = null, .destroy = null };
    const upload_arena = gpa.alloc(u8, UPLOAD_ARENA_SIZE) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
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
        .cmd_encoders = undefined,
        .cmd_valid = std.mem.zeroes([MAX_CMD_BUFFERS]bool),
        .compute_records = undefined,
        .upload_records = undefined,
        .upload_count = std.atomic.Value(u32).init(0),
        .upload_arena = upload_arena,
        .upload_arena_offset = std.atomic.Value(usize).init(0),
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
        .white_texture = .{ .idx = c.KE_HANDLE_NONE },
        .ndc = dev.get_ndc_convention.?(dev),
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
        .clear_value = .{ 0, 0, 0, 0 }, // defer to core's global clear_color
    };
    st.resource_count = 1;

    const core = gpa.create(c.ke_render_core) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    core.* = .{
        .handle = st,
        .declare = resource_table.declare,
        .import_texture = resource_table.importTexture,
        .cid = resource_table.cidOf,
        .begin_pass = pass_recording.beginPass,
        .end_pass = pass_recording.endPass,
        .begin_frame = frame_lifecycle.beginFrame,
        .end_frame = frame_lifecycle.endFrame,
        .upload = frame_lifecycle.uploadBuffer,
        .upload_mesh = asset_upload.uploadMesh,
        .mesh_buffers = asset_upload.meshBuffers,
        .set_clear_color = asset_upload.setClearColor,
        .upload_texture = asset_upload.uploadTexture,
        .create_material = asset_upload.createMaterial,
        .material_layout = asset_upload.materialLayout,
        .material_bind_group = asset_upload.materialBindGroup,
        .upload_cubemap = asset_upload.uploadCubemap,
        .texture_view = asset_upload.textureView,
        .sampler = asset_upload.samplerOf,
        .resource_view = resource_table.resourceView,
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
    st.white_texture = asset_upload.uploadTexture(core, 1, 1, &white_px, null); // texture 0 = white albedo
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 }; // (0,0,1) in tangent space
    st.default_normal = asset_upload.uploadTexture(core, 1, 1, &flat_normal_px, null);
    const black_cube_px = [_]u8{0} ** (4 * 6); // 1×1 black on all 6 faces
    st.default_cubemap = asset_upload.uploadCubemap(core, 1, &black_cube_px, null);
    const white_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    _ = asset_upload.createMaterial(core, &white_color, 0.0, 0.5, .{ .idx = c.KE_HANDLE_NONE }, .{ .idx = c.KE_HANDLE_NONE }, null);

    return .{ .ref = core, .destroy = destroyCore };
}
