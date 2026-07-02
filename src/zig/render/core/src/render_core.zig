const std = @import("std");
const zm = @import("zmath");

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
const NUM_PRECREATED_ENCODERS = 8; // command encoders pre-created per frame (≥ pass count)
const MAX_COLOR_ATTACH = 8;
const MAX_MESHES = 256;
const MAX_TEXTURES = 256;
const MAX_MATERIALS = 256;
const MAX_UPLOADS = 4096; // deferred buffer uploads per frame
const UPLOAD_ARENA_SIZE = 8 * 1024 * 1024; // per-frame staging for upload data copies

// UI overlay: quads accumulate here across the frame (ui_quad calls from any
// thread before the pass runs) and are flushed as one dynamic vertex buffer by
// the ui pass. 6 vertices per quad (two triangles, no index buffer — the count
// per frame is small enough that indexing isn't worth the complexity).
const MAX_UI_QUADS = 8192;
const MAX_UI_BATCHES = 512;
const UiVertex = extern struct {
    position: [2]f32,
    uv: [2]f32,
    color: [4]f32,
};
const UiBatch = struct {
    texture_idx: u32,
    first_vertex: u32,
    vertex_count: u32,
};

// A deferred buffer upload. wgpuQueueWriteBuffer is NOT safe to call concurrently
// with render-pass recording on wgpu-native (it deadlocks), so `upload` records
// here lock-free from any pass thread and end_frame replays the writes single-
// threaded before the submit (queue-ordered, so the data lands before the draws).
const UploadRecord = struct {
    buffer: c.ke_gpu_buffer,
    gpu_offset: u64,
    arena_offset: usize,
    size: usize,
};

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
    // Per-resource clear color. [3]==0 (default) defers to core's global clear_color.
    clear_value: [4]f32,
};

// Accumulated compute-pass recording. On wgpu-native, recording a compute pass
// concurrently with a render pass deadlocks; render-pass recording across distinct
// encoders is safe. So begin_compute hands back a recording proxy that appends the
// commands to one of these (pure CPU writes, safe on any pass thread); end_frame
// replays them into a real compute pass single-threaded. The pass author calls the
// same ke_gpu_compute_pass interface and never sees the difference.
const MAX_COMPUTE_CMDS = 32;
const ComputeCmd = union(enum) {
    set_pipeline: c.ke_gpu_pipeline,
    set_bind_group: struct { index: u32, bg: c.ke_gpu_bind_group, offsets: [4]u32, count: u32 },
    dispatch: struct { x: u32, y: u32, z: u32 },
    dispatch_indirect: struct { buf: c.ke_gpu_buffer, offset: usize },
};
const ComputeRecord = struct {
    pass: c.ke_gpu_compute_pass, // synthesized object handed to the pass body
    cmds: [MAX_COMPUTE_CMDS]ComputeCmd,
    count: u32,
    valid: bool, // a compute pass recorded into this slot this frame
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

    // UI overlay pipeline + per-frame quad buffer. vertices accumulate through
    // ui_quad (single-threaded — called from the ordinary system-execute path,
    // never from a parallel wave body) and are uploaded + drawn by the ui pass.
    ui_pipeline: c.ke_gpu_pipeline,
    ui_bgl_frame: c.ke_gpu_bind_group_layout, // set 0: proj uniform
    ui_bgl_tex: c.ke_gpu_bind_group_layout, // set 1: texture + sampler
    ui_frame_uniform: c.ke_gpu_buffer,
    ui_frame_bind_group: c.ke_gpu_bind_group,
    ui_vbo: c.ke_gpu_buffer,
    ui_vertices: [MAX_UI_QUADS * 6]UiVertex,
    ui_vertex_count: u32,
    // Consecutive same-texture quads batch into one draw call (sprite-batching —
    // texture switches are the only thing that splits a batch). Sized generously;
    // a caller alternating textures every quad still degrades gracefully (no
    // crash, just more draw calls up to MAX_UI_BATCHES).
    ui_batches: [MAX_UI_BATCHES]UiBatch,
    ui_batch_count: u32,
    ui_bind_group_cache: [MAX_TEXTURES]c.ke_gpu_bind_group, // lazily built, keyed by texture index; INVALID_HANDLE = unbuilt

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
    is_compute: bool, // set when begin_compute was called → recording was accumulated
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
        .clear_value = desc.*.clear_value,
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
        .clear_value = .{ 0, 0, 0, 0 },
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
    // Use this pass's pre-created encoder (made serially in begin_frame) so the
    // non-thread-safe create_command_encoder never runs on parallel pass threads.
    const slot = io.*.cmd_slot;
    const enc = if (slot < NUM_PRECREATED_ENCODERS) st.cmd_encoders[slot] else st.device.create_command_encoder.?(st.device);
    ps.* = .{
        .core = st,
        .io = io.*,
        .encoder = enc,
        .is_compute = false,
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
    // Park the encoder in this pass's slot; end_frame finishes it single-threaded.
    // The encoder outlives this call (it is NOT destroyed here). Distinct slots →
    // no race with a parallel pass. A compute pass recorded nothing into the encoder
    // (its commands were accumulated in compute_records[slot]); cmd_valid stays false
    // so end_frame replays the compute record into this slot's encoder instead.
    const slot = ps.io.cmd_slot;
    if (slot < MAX_CMD_BUFFERS) {
        st.cmd_encoders[slot] = ps.encoder;
        st.cmd_valid[slot] = !ps.is_compute;
    } else {
        ps.encoder.destroy.?(ps.encoder); // unreachable in practice; avoid a leak
    }
    gpa.destroy(ps);
    gpa.destroy(@as(*c.ke_render_pass_ctx, @ptrCast(ctx)));
}

fn beginFrame(self: [*c]c.ke_render_core, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_bool {
    _ = out_error;
    const st = coreOf(self);
    @memset(st.cmd_valid[0..], false); // open the frame: no pass has recorded yet
    for (&st.compute_records) |*r| {
        r.valid = false;
        r.count = 0;
    }
    st.upload_count.store(0, .monotonic); // reset the deferred-upload collector
    st.upload_arena_offset.store(0, .monotonic);
    // uiReset happens at the END of the ui pass (uiDraw), not here — see uiDraw.
    // Resetting here would wipe quads a system in an EARLIER phase (e.g. Update)
    // queued for THIS frame's ui pass to draw, since begin_frame is itself an
    // ordinary render-phase system with no ordering guarantee relative to systems
    // registered by other modules ahead of the render module in load order.
    // Pre-create this frame's command encoders single-threaded; parallel passes
    // record into theirs without calling the non-thread-safe create function.
    var pe: u32 = 0;
    while (pe < NUM_PRECREATED_ENCODERS) : (pe += 1) {
        st.cmd_encoders[pe] = st.device.create_command_encoder.?(st.device);
    }
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

    // Flush the frame's deferred uploads single-threaded — wgpuQueueWriteBuffer is
    // not safe concurrently with pass recording, so this is the only place it runs.
    // Queue writes are ordered before the submit below, so the data lands in time.
    const ucount = @min(st.upload_count.load(.monotonic), MAX_UPLOADS);
    var u: u32 = 0;
    while (u < ucount) : (u += 1) {
        const r = st.upload_records[u];
        st.device.write_buffer.?(st.device, r.buffer, r.gpu_offset, &st.upload_arena[r.arena_offset], r.size);
    }

    // Build the frame's command buffers single-threaded (the device's command-buffer
    // registry is not thread-safe), in ascending slot order = dependency order. A
    // render slot finishes its parked encoder; a compute slot replays its accumulated
    // recording into that slot's encoder here — the one place compute recording runs,
    // so it never races a concurrently-recording render pass.
    var submit: [MAX_CMD_BUFFERS][*c]c.ke_gpu_command_buffer = undefined;
    var n: u32 = 0;
    var s: u32 = 0;
    while (s < MAX_CMD_BUFFERS) : (s += 1) {
        if (st.cmd_valid[s]) {
            const enc = st.cmd_encoders[s];
            submit[n] = enc.*.finish.?(enc);
            n += 1;
        } else if (st.compute_records[s].valid) {
            const enc = st.cmd_encoders[s];
            const rec = &st.compute_records[s];
            const cp = enc.*.begin_compute_pass.?(enc);
            var ci: u32 = 0;
            while (ci < rec.count) : (ci += 1) {
                switch (rec.cmds[ci]) {
                    .set_pipeline => |p| cp.*.set_pipeline.?(cp, p),
                    .set_bind_group => |b| {
                        if (b.count > 0)
                            cp.*.set_bind_group.?(cp, b.index, b.bg, &b.offsets, b.count)
                        else
                            cp.*.set_bind_group.?(cp, b.index, b.bg, null, 0);
                    },
                    .dispatch => |d| cp.*.dispatch.?(cp, d.x, d.y, d.z),
                    .dispatch_indirect => |d| cp.*.dispatch_indirect.?(cp, d.buf, d.offset),
                }
            }
            cp.*.end.?(cp);
            submit[n] = enc.*.finish.?(enc);
            n += 1;
        }
    }
    if (n > 0) {
        st.device.queue_submit.?(st.device, st.queue, &submit, n);
        var i: u32 = 0;
        while (i < n) : (i += 1) submit[i].*.destroy.?(submit[i]);
        @memset(st.cmd_valid[0..], false);
    }
    // Release this frame's pre-created encoders (whether or not a pass used them).
    var pe: u32 = 0;
    while (pe < NUM_PRECREATED_ENCODERS) : (pe += 1) {
        const enc = st.cmd_encoders[pe];
        enc.*.destroy.?(enc);
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

// Records a deferred upload — lock-free, callable from any pass thread. The index
// and the arena slice are each reserved with an atomic bump, then the data is copied
// in. end_frame replays the records single-threaded (wgpuQueueWriteBuffer is unsafe
// concurrently with pass recording on wgpu-native).
fn uploadBuffer(self: [*c]c.ke_render_core, buffer: c.ke_gpu_buffer, offset: u64, data: ?*const anyopaque, size: usize) callconv(.c) void {
    if (size == 0 or data == null) return;
    const st = coreOf(self);
    const idx = st.upload_count.fetchAdd(1, .monotonic);
    if (idx >= MAX_UPLOADS) return; // overflow — raise MAX_UPLOADS if ever hit
    const aoff = st.upload_arena_offset.fetchAdd(size, .monotonic);
    if (aoff + size > st.upload_arena.len) return; // arena overflow — raise the size
    const src: [*]const u8 = @ptrCast(data);
    @memcpy(st.upload_arena[aoff .. aoff + size], src[0..size]);
    st.upload_records[idx] = .{ .buffer = buffer, .gpu_offset = offset, .arena_offset = aoff, .size = size };
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

// sRGB → linear (IEC 61966-2-1). Authored base colors are sRGB; lighting runs in
// linear space, so the factor is linearized once here (the final pass re-encodes
// to sRGB on output). Alpha is not a color channel and stays as-is.
fn srgbToLinear(cs: f32) f32 {
    return if (cs <= 0.04045) cs / 12.92 else std.math.pow(f32, (cs + 0.055) / 1.055, 2.4);
}

fn createMaterial(self: [*c]c.ke_render_core, base_color: [*c]const f32,
                  metallic: f32, roughness: f32, albedo: c.ke_texture_handle,
                  normal: c.ke_texture_handle, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_material_handle {
    _ = out_error;
    const st = coreOf(self);
    if (st.material_count >= MAX_MATERIALS) return .{ .idx = c.KE_HANDLE_NONE };

    // std140: float4 base_color (linearized) + (metallic, roughness) packed next.
    const mat_data = [8]f32{
        srgbToLinear(base_color[0]), srgbToLinear(base_color[1]), srgbToLinear(base_color[2]), base_color[3],
        metallic,                    roughness,                   0.0,                         0.0,
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

fn resourceView(self: [*c]c.ke_render_core, name: [*c]const u8) callconv(.c) c.ke_gpu_texture_view {
    const r = coreOf(self).find(name) orelse return c.KE_GPU_INVALID_HANDLE;
    return r.view;
}

// ── UI overlay draw list ──────────────────────────────────────────────────

// Resets the accumulator at the start of each frame (called by begin_frame).
fn uiReset(st: *CoreState) void {
    st.ui_vertex_count = 0;
    st.ui_batch_count = 0;
}

fn uiQuad(self: [*c]c.ke_render_core, texture: c.ke_texture_handle,
          dst_x: f32, dst_y: f32, dst_w: f32, dst_h: f32,
          uv0: f32, uv1: f32, uv2: f32, uv3: f32,
          r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    const st = coreOf(self);
    if (st.ui_vertex_count + 6 > st.ui_vertices.len) return;

    const tex_idx = if (texture.idx == c.KE_HANDLE_NONE) st.white_texture.idx else texture.idx;

    // Extend the current batch if the texture matches; otherwise open a new one.
    const need_new_batch = st.ui_batch_count == 0 or
        st.ui_batches[st.ui_batch_count - 1].texture_idx != tex_idx;
    if (need_new_batch) {
        if (st.ui_batch_count >= st.ui_batches.len) return;
        st.ui_batches[st.ui_batch_count] = .{
            .texture_idx = tex_idx,
            .first_vertex = st.ui_vertex_count,
            .vertex_count = 0,
        };
        st.ui_batch_count += 1;
    }

    const x0 = dst_x;
    const y0 = dst_y;
    const x1 = dst_x + dst_w;
    const y1 = dst_y + dst_h;
    const col = [4]f32{ r, g, b, a };

    const verts = [6]UiVertex{
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y0 }, .uv = .{ uv2, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y0 }, .uv = .{ uv0, uv1 }, .color = col },
        .{ .position = .{ x1, y1 }, .uv = .{ uv2, uv3 }, .color = col },
        .{ .position = .{ x0, y1 }, .uv = .{ uv0, uv3 }, .color = col },
    };
    @memcpy(st.ui_vertices[st.ui_vertex_count .. st.ui_vertex_count + 6], &verts);
    st.ui_vertex_count += 6;
    st.ui_batches[st.ui_batch_count - 1].vertex_count += 6;
}

// The set-1 (texture+sampler) bind group for a texture index, built once and
// cached — UI textures (font atlases, a handful of solid-color sources) are
// stable across frames, so rebuilding every quad would be wasteful.
fn uiBindGroupFor(st: *CoreState, tex_idx: u32) c.ke_gpu_bind_group {
    if (st.ui_bind_group_cache[tex_idx] != c.KE_GPU_INVALID_HANDLE)
        return st.ui_bind_group_cache[tex_idx];

    const view = (st.textureAt(tex_idx) orelse &st.textures[st.white_texture.idx]).view;
    const entries = [_]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = st.sampler },
    };
    const bg = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .layout = st.ui_bgl_tex,
        .entry_count = 2,
        .entries = &entries,
    });
    st.ui_bind_group_cache[tex_idx] = bg;
    return bg;
}

const ui_vs_wgsl = @embedFile("ui.vs.wgsl");
const ui_fs_wgsl = @embedFile("ui.fs.wgsl");

// Pipeline + buffers for the UI overlay pass. Called once from core create.
// Premultiplied-alpha blend so both solid quads and glyph coverage composite
// correctly over whatever the tonemap pass already wrote.
fn uiSetup(st: *CoreState, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_vs_wgsl), .byte_size = ui_vs_wgsl.len, .entry_point = "ui.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(ui_fs_wgsl), .byte_size = ui_fs_wgsl.len, .entry_point = "ui.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    const frame_bgl_entry = c.ke_gpu_bind_group_layout_entry{
        .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_VERTEX,
        .type = c.KE_GPU_BINDING_TYPE_BUFFER, .has_dynamic_offset = 0, .view_dimension = 0,
    };
    st.ui_bgl_frame = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 1,
        .entries = &frame_bgl_entry,
    });

    const tex_bgl_entries = [_]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    st.ui_bgl_tex = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &tex_bgl_entries,
    });

    const attrs = [_]c.ke_gpu_vertex_attribute{
        .{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "position") },
        .{ .shader_location = 1, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X2, .offset = @offsetOf(UiVertex, "uv") },
        .{ .shader_location = 2, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X4, .offset = @offsetOf(UiVertex, "color") },
    };
    const vbl = c.ke_gpu_vertex_buffer_layout{
        .stride = @sizeOf(UiVertex),
        .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX,
        .attribute_count = 3,
        .attributes = &attrs,
    };

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
    pp.bind_group_layouts[0] = st.ui_bgl_frame;
    pp.bind_group_layouts[1] = st.ui_bgl_tex;
    pp.bind_group_layout_count = 2;
    // Premultiplied-alpha over: dst = src + dst*(1-src.a). The color channel
    // reads ONE (not SRC_ALPHA) because uiQuad's caller already premultiplies.
    pp.blend_state.blend_enabled = 1;
    pp.blend_state.src_color = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_color = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.color_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.src_alpha = c.KE_GPU_BLEND_FACTOR_ONE;
    pp.blend_state.dst_alpha = c.KE_GPU_BLEND_FACTOR_ONE_MINUS_SRC_ALPHA;
    pp.blend_state.alpha_op = c.KE_GPU_BLEND_OP_ADD;
    pp.blend_state.write_mask = 0x0F;
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    pp.color_target_format = 0; // swapchain surface format (backbuffer)

    st.ui_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.ui_pipeline == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ui pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    st.ui_frame_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = 64, // float4x4
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });
    const frame_entry = c.ke_gpu_bind_group_entry{
        .binding = 0, .type = c.KE_GPU_BINDING_TYPE_BUFFER,
        .buffer = st.ui_frame_uniform, .buffer_offset = 0, .buffer_size = 64,
        .texture_view = 0, .sampler = 0,
    };
    st.ui_frame_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.ui_bgl_frame,
        .entry_count = 1,
        .entries = &frame_entry,
    });

    st.ui_vbo = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{
        .initial_data = null,
        .size = st.ui_vertices.len * @sizeOf(UiVertex),
        .usage = c.KE_GPU_BUFFER_USAGE_VERTEX | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    });

    st.ui_vertex_count = 0;
    st.ui_batch_count = 0;
    for (&st.ui_bind_group_cache) |*e| e.* = c.KE_GPU_INVALID_HANDLE;
    return true;
}

// Uploads this frame's accumulated quads and draws each texture batch. Called
// by the module's "render.ui" pass — after uiQuad calls from earlier systems
// (the wave builder orders it last by cmd_slot, see render_module.zig).
fn uiDraw(self: [*c]c.ke_render_core, sys: ?*c.ke_system_ctx, io: [*c]const c.ke_render_pass_io) callconv(.c) void {
    const st = coreOf(self);
    if (st.ui_vertex_count == 0) return;

    const pc = self.*.begin_pass.?(self, sys, io);
    if (pc == null) return;

    // Pixel-space (top-left origin) → clip space, honoring the backend's NDC.
    var bw: u32 = 0;
    var bh: u32 = 0;
    pc.*.backbuffer_size.?(pc, &bw, &bh);
    var proj = zm.orthographicOffCenterLh(0.0, @floatFromInt(bw), 0.0, @floatFromInt(bh), 0.0, 1.0);
    if (st.ndc.y_flip != 0) proj[1][1] = -proj[1][1];
    var proj_arr: [16]f32 = undefined;
    zm.storeMat(proj_arr[0..], proj);
    self.*.upload.?(self, st.ui_frame_uniform, 0, &proj_arr, 64);

    const bytes = std.mem.sliceAsBytes(st.ui_vertices[0..st.ui_vertex_count]);
    self.*.upload.?(self, st.ui_vbo, 0, bytes.ptr, bytes.len);

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.ui_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.ui_frame_bind_group, null, 0);
    rp.*.set_vertex_buffer.?(rp, 0, st.ui_vbo, 0);

    var i: u32 = 0;
    while (i < st.ui_batch_count) : (i += 1) {
        const batch = st.ui_batches[i];
        rp.*.set_bind_group.?(rp, 1, uiBindGroupFor(st, batch.texture_idx), null, 0);
        rp.*.draw.?(rp, batch.vertex_count, 1, batch.first_vertex, 0);
    }
    rp.*.end.?(rp);
    self.*.end_pass.?(self, pc);

    // Vertex/batch data is already copied into the upload arena (uploadBuffer
    // memcpy's synchronously) and the draw commands reference GPU buffer handles,
    // not this CPU array — safe to reset now, ready for the next frame's queuing.
    uiReset(st);
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
            // Use per-resource clear when alpha != 0 (explicit override); otherwise
            // fall back to the core's global scene clear color.
            const cv: [4]f32 = if (r.clear_value[3] != 0.0)
                r.clear_value
            else
                ps.core.clear_color;
            colors[color_count] = .{
                .view = r.view,
                .load_op = if (ps.io.load != 0) c.KE_GPU_LOAD_OP_LOAD else c.KE_GPU_LOAD_OP_CLEAR,
                .store_op = c.KE_GPU_STORE_OP_STORE,
                .clear_value = .{ .color = cv },
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

// Opens compute recording. Instead of a live device compute pass (recording one
// concurrently with a render pass deadlocks on wgpu-native), it hands back a proxy
// that appends the commands to this slot's compute_records; end_frame replays them
// single-threaded. The pass body uses the same ke_gpu_compute_pass interface.
fn ctxBeginCompute(self: [*c]c.ke_render_pass_ctx) callconv(.c) [*c]c.ke_gpu_compute_pass {
    const ps = passOf(self);
    ps.is_compute = true;
    const slot = ps.io.cmd_slot;
    if (slot >= MAX_CMD_BUFFERS) return null;
    const rec = &ps.core.compute_records[slot];
    rec.count = 0;
    rec.valid = true;
    rec.pass = .{
        .handle = rec,
        .device = ps.core.device,
        .set_pipeline = cpSetPipeline,
        .set_bind_group = cpSetBindGroup,
        .dispatch = cpDispatch,
        .dispatch_indirect = cpDispatchIndirect,
        .end = cpEnd,
    };
    return &rec.pass;
}

inline fn recOf(self: [*c]c.ke_gpu_compute_pass) *ComputeRecord {
    return @alignCast(@ptrCast(self.*.handle));
}
fn cpAppend(rec: *ComputeRecord, cmd: ComputeCmd) void {
    if (rec.count >= MAX_COMPUTE_CMDS) return; // overflow — raise MAX_COMPUTE_CMDS
    rec.cmds[rec.count] = cmd;
    rec.count += 1;
}
fn cpSetPipeline(self: [*c]c.ke_gpu_compute_pass, pipe: c.ke_gpu_pipeline) callconv(.c) void {
    cpAppend(recOf(self), .{ .set_pipeline = pipe });
}
fn cpSetBindGroup(self: [*c]c.ke_gpu_compute_pass, group_index: u32, bg: c.ke_gpu_bind_group,
                  dynamic_offsets: [*c]const u32, dyn_count: u32) callconv(.c) void {
    var off: [4]u32 = .{ 0, 0, 0, 0 };
    const n = @min(dyn_count, 4);
    var i: u32 = 0;
    while (i < n) : (i += 1) off[i] = dynamic_offsets[i];
    cpAppend(recOf(self), .{ .set_bind_group = .{ .index = group_index, .bg = bg, .offsets = off, .count = dyn_count } });
}
fn cpDispatch(self: [*c]c.ke_gpu_compute_pass, x: u32, y: u32, z: u32) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch = .{ .x = x, .y = y, .z = z } });
}
fn cpDispatchIndirect(self: [*c]c.ke_gpu_compute_pass, indirect_buf: c.ke_gpu_buffer, offset: usize) callconv(.c) void {
    cpAppend(recOf(self), .{ .dispatch_indirect = .{ .buf = indirect_buf, .offset = offset } });
}
fn cpEnd(self: [*c]c.ke_gpu_compute_pass) callconv(.c) void {
    _ = self; // end is implicit — the replay in end_frame ends the real pass
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
    gpa.free(st.upload_arena);
    gpa.destroy(st);
    gpa.destroy(@as(*c.ke_render_core, @ptrCast(self)));
}

export fn ke_render_core_create(device: ?*c.ke_gpu_device, ecs: ?*c.ke_ecs, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_core_handle {
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
        .ui_pipeline = c.KE_GPU_INVALID_HANDLE,
        .ui_bgl_frame = c.KE_GPU_INVALID_HANDLE,
        .ui_bgl_tex = c.KE_GPU_INVALID_HANDLE,
        .ui_frame_uniform = c.KE_GPU_INVALID_HANDLE,
        .ui_frame_bind_group = c.KE_GPU_INVALID_HANDLE,
        .ui_vbo = c.KE_GPU_INVALID_HANDLE,
        .ui_vertices = undefined,
        .ui_vertex_count = 0,
        .ui_batches = undefined,
        .ui_batch_count = 0,
        .ui_bind_group_cache = undefined,
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
        .declare = declare,
        .import_texture = importTexture,
        .cid = cidOf,
        .begin_pass = beginPass,
        .end_pass = endPass,
        .begin_frame = beginFrame,
        .end_frame = endFrame,
        .upload = uploadBuffer,
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
        .resource_view = resourceView,
        .ui_quad = uiQuad,
        .ui_draw = uiDraw,
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
    st.white_texture = uploadTexture(core, 1, 1, &white_px, null); // texture 0 = white albedo
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 }; // (0,0,1) in tangent space
    st.default_normal = uploadTexture(core, 1, 1, &flat_normal_px, null);
    const black_cube_px = [_]u8{0} ** (4 * 6); // 1×1 black on all 6 faces
    st.default_cubemap = uploadCubemap(core, 1, &black_cube_px, null);
    const white_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    _ = createMaterial(core, &white_color, 0.0, 0.5, .{ .idx = c.KE_HANDLE_NONE }, .{ .idx = c.KE_HANDLE_NONE }, null);

    if (!uiSetup(st, out_error)) {
        gpa.destroy(core);
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    }

    return .{ .ref = core, .destroy = destroyCore };
}
