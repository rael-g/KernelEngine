//! The root of the render service plugin: the state every file of the plugin works on and the one
//! factory that builds it and fills the `ke_render_service` vtable.

const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_service").logFn };

pub const abi_io = @import("abi_io");
const abi_math = @import("abi_math");
const abi_render = @import("abi_render");
const abi_render_service_factory = @import("abi_render_service_factory");
const abi_resource_cache = @import("abi_resource_cache");
const abi_resource_cache_default_factory = @import("abi_resource_cache_default_factory");
const abi_result = @import("abi_result");
/// The error set and code conversions every file of the service fails through.
pub const R = @import("result").Result(.{});

const heap = @import("heap");
pub const gpa = heap.gpa;

const blit_mod = @import("blit.zig");
const frame_lifecycle = @import("frame_lifecycle.zig");
const asset_upload = @import("asset_upload.zig");
const pipeline_cache = @import("pipeline_cache.zig");
const slot_map = @import("slot_map.zig");
const shader_loader = @import("shader_loader.zig");
const frame_globals = @import("frame_globals.zig");

pub const first_upload_records = 4096;
pub const MAX_SHADER_NAME = 64;
pub const DEFAULT_MATERIAL_SHADER = "standard";
const first_upload_arena = 8 * 1024 * 1024;

/// One buffer write queued during a frame: where it goes on the GPU and the bytes it copies out
/// of the upload arena.
pub const UploadRecord = struct {
    buffer: abi_asset_resolver.c.ke_gpu_buffer,
    gpu_offset: u64,
    arena_offset: usize,
    size: usize,
};

/// An upload that found the arena or the records full, in a block of its own, linked onto
/// `upload_spill` by the thread that made it.
pub const SpilledUpload = struct {
    next: ?*SpilledUpload,
    buffer: abi_asset_resolver.c.ke_gpu_buffer,
    gpu_offset: u64,
    data: []u8,
};

/// A mesh in `mesh_store`: the vertex and index buffers it owns and the number of indices.
pub const Mesh = struct {
    vbo: abi_asset_resolver.c.ke_gpu_buffer,
    ibo: abi_asset_resolver.c.ke_gpu_buffer,
    index_count: u32,
};

/// A texture in `texture_store`: the GPU texture it owns and its default view.
pub const Texture = struct {
    tex: abi_asset_resolver.c.ke_gpu_texture,
    view: abi_asset_resolver.c.ke_gpu_texture_view,
};

/// A material in `material_store`: what the binder holds for it, its alpha mode and cutoff, the
/// name of its shader, and the albedo and normal textures it samples.
pub const Material = struct {
    binding: abi_asset_resolver.c.ke_render_material_binding,
    alpha_mode: abi_render_handles.c.ke_alpha_mode,
    alpha_cutoff: f32,
    shader: [MAX_SHADER_NAME]u8,
    albedo: abi_render_handles.c.ke_texture_handle,
    normal: abi_render_handles.c.ke_texture_handle,
};

/// The state a render service is built on. `ke_render_service_create` makes it and `destroyCore`
/// frees it. `materialAt` falls
/// back to `white_material` for a handle it does not know. The two upload counters are atomic.
pub const CoreState = struct {
    device: *abi_render_gpu.c.ke_gpu_device,
    target: *abi_render_gpu.c.ke_gpu_render_target,
    binder: *abi_render_gpu.c.ke_render_resource_binder,
    queue: abi_asset_resolver.c.ke_gpu_queue,

    backbuffer_w: u32,
    backbuffer_h: u32,

    frame_live: bool,

    upload_records: []UploadRecord,
    upload_spill: std.atomic.Value(?*SpilledUpload),
    upload_count: std.atomic.Value(u32),
    upload_arena: []u8,
    upload_arena_offset: std.atomic.Value(usize),

    mesh_store: slot_map.SlotMap(Mesh),
    texture_store: slot_map.SlotMap(Texture),
    material_store: slot_map.SlotMap(Material),
    mesh_cache: *abi_resource_cache.c.ke_resource_cache,
    texture_cache: *abi_resource_cache.c.ke_resource_cache,
    material_cache: *abi_resource_cache.c.ke_resource_cache,
    mesh_cache_destroy: *const fn (*abi_resource_cache.c.ke_resource_cache) callconv(.c) void,
    texture_cache_destroy: *const fn (*abi_resource_cache.c.ke_resource_cache) callconv(.c) void,
    material_cache_destroy: *const fn (*abi_resource_cache.c.ke_resource_cache) callconv(.c) void,

    shader_store: slot_map.SlotMap(abi_asset_resolver.c.ke_gpu_shader_module),
    shader_cache: *abi_resource_cache.c.ke_resource_cache,
    shader_cache_destroy: *const fn (*abi_resource_cache.c.ke_resource_cache) callconv(.c) void,
    shader_dir: []const u8,
    io: *abi_io.c.ke_io,
    shader_reads: std.atomic.Value(?*shader_loader.Read) = .init(null),

    globals: frame_globals.Globals,
    default_normal: abi_render_handles.c.ke_texture_handle,
    default_cubemap: abi_render_handles.c.ke_texture_handle,
    white_texture_h: abi_render_handles.c.ke_texture_handle,
    white_material: abi_render_handles.c.ke_material_handle,

    ndc: abi_render_gpu.c.ke_ndc_convention,

    pipeline_cache: pipeline_cache.PipelineCache,

    api: [*c]abi_render.c.ke_render_service = null,
    blit: blit_mod.Blit = .{},

    /// Null when the handle is stale or was never issued.
    pub fn meshAt(self: *CoreState, h: abi_render_handles.c.ke_mesh_handle) ?*Mesh {
        return self.mesh_store.get(h.bits);
    }

    /// Null when the handle is stale or was never issued.
    pub fn textureAt(self: *CoreState, h: abi_render_handles.c.ke_texture_handle) ?*Texture {
        return self.texture_store.get(h.bits);
    }

    pub fn materialAt(self: *CoreState, h: abi_render_handles.c.ke_material_handle) *Material {
        return self.material_store.get(h.bits) orelse
            self.material_store.get(self.white_material.bits).?;
    }

};

/// The state behind a render service vtable.
pub inline fn coreOf(self: [*c]abi_render.c.ke_render_service) *CoreState {
    return @ptrCast(@alignCast(self.*.handle));
}
/// The service's `resource_binder` slot.
fn resourceBinder(self: [*c]abi_render.c.ke_render_service) callconv(.c) [*c]abi_render_gpu.c.ke_render_resource_binder {
    if (self == null) return null;
    return coreOf(self).binder;
}

/// The `destroy` of the handle `ke_render_service_create` returns. It flushes the device's pending
/// pipeline compiles first, so no compile still runs against what follows. It then releases the
/// blit, the caches and stores, the shared globals and the pipeline
/// cache, and frees the memory the state owns. After it, neither the state nor the
/// vtable is valid.
fn destroyCore(self: [*c]abi_render.c.ke_render_service) callconv(.c) void {
    const st = coreOf(self);
    if (st.device.flush_pipeline_compiles) |flush| flush(st.device);
    st.blit.release(st.binder);
    st.material_cache_destroy(st.material_cache);
    st.texture_cache_destroy(st.texture_cache);
    st.mesh_cache_destroy(st.mesh_cache);
    shader_loader.releaseReads(st);
    st.shader_cache_destroy(st.shader_cache);
    st.material_store.deinit();
    st.texture_store.deinit();
    st.mesh_store.deinit();
    st.shader_store.deinit();
    st.globals.release(st.device);
    st.pipeline_cache.destroyAll(st.device);
    var spilled = st.upload_spill.swap(null, .acquire);
    while (spilled) |n| {
        spilled = n.next;
        gpa.free(n.data);
        gpa.destroy(n);
    }
    gpa.free(st.upload_arena);
    gpa.free(st.upload_records);
    gpa.free(@constCast(st.shader_dir));
    gpa.destroy(st);
    gpa.destroy(@as(*abi_render.c.ke_render_service, @ptrCast(self)));
}

/// Builds the state and the vtable whole, or frees in reverse what it took and fails. The vtable's
/// handle is the state; the shared globals, the default resources and the blit shaders are not made
/// yet.
fn assemble(dev: *abi_render_gpu.c.ke_gpu_device, tgt: *abi_render_gpu.c.ke_gpu_render_target, bnd: *abi_render_gpu.c.ke_render_resource_binder, shader_dir_span: []const u8, io: *abi_io.c.ke_io) R.Error!*abi_render.c.ke_render_service {
    const st = try gpa.create(CoreState);
    errdefer gpa.destroy(st);
    const upload_arena = try gpa.alloc(u8, first_upload_arena);
    errdefer gpa.free(upload_arena);
    const upload_records = try gpa.alloc(UploadRecord, first_upload_records);
    errdefer gpa.free(upload_records);
    const shader_dir_owned = try gpa.dupe(u8, shader_dir_span);
    errdefer gpa.free(shader_dir_owned);
    var bb_w: u32 = 0;
    var bb_h: u32 = 0;
    tgt.size.?(tgt, &bb_w, &bb_h);
    st.* = .{
        .device = dev,
        .target = tgt,
        .binder = bnd,
        .queue = dev.get_default_queue.?(dev),
        .backbuffer_w = bb_w,
        .backbuffer_h = bb_h,
        .frame_live = false,
        .upload_records = upload_records,
        .upload_spill = std.atomic.Value(?*SpilledUpload).init(null),
        .upload_count = std.atomic.Value(u32).init(0),
        .upload_arena = upload_arena,
        .upload_arena_offset = std.atomic.Value(usize).init(0),
        .mesh_store = slot_map.SlotMap(Mesh).init(gpa),
        .texture_store = slot_map.SlotMap(Texture).init(gpa),
        .material_store = slot_map.SlotMap(Material).init(gpa),
        .mesh_cache = undefined,
        .texture_cache = undefined,
        .material_cache = undefined,
        .mesh_cache_destroy = undefined,
        .texture_cache_destroy = undefined,
        .material_cache_destroy = undefined,
        .shader_store = slot_map.SlotMap(abi_asset_resolver.c.ke_gpu_shader_module).init(gpa),
        .shader_cache = undefined,
        .shader_cache_destroy = undefined,
        .shader_dir = shader_dir_owned,
        .io = io,
        .globals = .{},
        .default_normal = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },
        .default_cubemap = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },
        .white_texture_h = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },
        .white_material = .{ .bits = abi_render_handles.c.KE_HANDLE_NONE },
        .ndc = dev.get_ndc_convention.?(dev),
        .pipeline_cache = pipeline_cache.PipelineCache.init(),
    };
    const mesh_ch = try resourceCache(asset_upload.destroyMeshResource, st);
    errdefer mesh_ch.destroy.?(mesh_ch.ref);
    const tex_ch = try resourceCache(asset_upload.destroyTextureResource, st);
    errdefer tex_ch.destroy.?(tex_ch.ref);
    const mat_ch = try resourceCache(asset_upload.destroyMaterialResource, st);
    errdefer mat_ch.destroy.?(mat_ch.ref);
    const shader_ch = try resourceCache(shader_loader.destroyShaderResource, st);
    errdefer shader_ch.destroy.?(shader_ch.ref);
    st.mesh_cache = mesh_ch.ref.?;
    st.texture_cache = tex_ch.ref.?;
    st.material_cache = mat_ch.ref.?;
    st.shader_cache = shader_ch.ref.?;
    st.mesh_cache_destroy = mesh_ch.destroy.?;
    st.texture_cache_destroy = tex_ch.destroy.?;
    st.material_cache_destroy = mat_ch.destroy.?;
    st.shader_cache_destroy = shader_ch.destroy.?;

    const core = try gpa.create(abi_render.c.ke_render_service);
    core.* = .{
        .handle = st,
        .begin_frame = frame_lifecycle.beginFrame,
        .submit_uploads = frame_lifecycle.submitUploads,
        .end_frame = frame_lifecycle.endFrame,
        .blit = frame_lifecycle.blit,
        .upload = frame_lifecycle.uploadBuffer,
        .upload_mesh = asset_upload.uploadMesh,
        .mesh_buffers = asset_upload.meshBuffers,
        .upload_texture = asset_upload.uploadTexture,
        .create_material = asset_upload.createMaterial,
        .material_binding = asset_upload.materialBinding,
        .material_alpha_mode = asset_upload.materialAlphaMode,
        .material_alpha_cutoff = asset_upload.materialAlphaCutoff,
        .upload_cubemap = asset_upload.uploadCubemap,
        .texture_view = asset_upload.textureView,
        .backbuffer_size = frame_lifecycle.backbufferSize,
        .get_or_create_pipeline = pipeline_cache.getOrCreatePipeline,
        .material_shader = asset_upload.materialShader,
        .retain_mesh = asset_upload.retainMesh,
        .release_mesh = asset_upload.releaseMesh,
        .retain_texture = asset_upload.retainTexture,
        .release_texture = asset_upload.releaseTexture,
        .retain_material = asset_upload.retainMaterial,
        .release_material = asset_upload.releaseMaterial,
        .try_get_mesh = asset_upload.tryGetMesh,
        .try_get_texture = asset_upload.tryGetTexture,
        .try_get_material = asset_upload.tryGetMaterial,
        .white_texture = asset_upload.whiteTexture,
        .load_shader = shader_loader.loadShader,
        .set_frame_globals = frame_globals.setFrameGlobals,
        .frame_globals = frame_globals.frameGlobals,
        .set_lighting = frame_globals.setLighting,
        .lighting = frame_globals.lightingOf,
        .resource_binder = resourceBinder,
        .backbuffer_format = frame_lifecycle.backbufferFormat,
    };
    return core;
}

fn resourceCache(destroy_fn: abi_resource_cache.c.ke_resource_destroy_func, st: *CoreState) R.Error!abi_resource_cache.c.ke_resource_cache_handle {
    var h: abi_resource_cache.c.ke_resource_cache_handle = undefined;
    try R.check(abi_resource_cache_default_factory.c.ke_resource_cache_create(destroy_fn, st, &h));
    return h;
}

/// The factory of the render service, applying `config` as given. It builds in an order its steps
/// depend on: the target's size and the device's queue and NDC convention, then the resource caches,
/// each given its destroy function and the state as context, then the vtable, then the shared
/// globals, which it gives the binder. The default resources and the "blit" shaders come last
/// because they go through the functions of the vtable just built. `destroyCore` undoes this in
/// reverse and frees the vtable last. A null dependency, config or shader directory fails as an
/// invalid argument; a step that fails fails the factory with its code. On success the ref is the new
/// vtable and `destroy` is `destroyCore`.
export fn ke_render_service_create(
    device: ?*abi_render_gpu.c.ke_gpu_device,
    target: ?*abi_render_gpu.c.ke_gpu_render_target,
    io: ?*abi_io.c.ke_io,
    binder: ?*abi_render_gpu.c.ke_render_resource_binder,
    shader_dir_in: ?[*:0]const u8,
    out_service: [*c]abi_render.c.ke_render_service_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_service orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const dev = device orelse return R.code(error.InvalidArgument);
    const tgt = target orelse return R.code(error.InvalidArgument);
    const files = io orelse return R.code(error.InvalidArgument);
    const bnd = binder orelse return R.code(error.InvalidArgument);
    const shader_dir = shader_dir_in orelse return R.code(error.InvalidArgument);

    const core = assemble(dev, tgt, bnd, std.mem.span(shader_dir), files) catch |err| return R.code(err);
    prepare(core) catch |err| {
        destroyCore(core);
        return R.code(err);
    };
    out.* = .{ .ref = core, .destroy = destroyCore };
    return R.ok;
}

fn prepare(core: *abi_render.c.ke_render_service) R.Error!void {
    const st = coreOf(core);
    try st.globals.create(st.device);
    try st.globals.provideTo(st.binder);
    const white_px = [_]u8{ 255, 255, 255, 255 };
    try R.check(asset_upload.uploadTexture(core, "__ke_white_texture", 1, 1, &white_px, white_px.len, &st.white_texture_h));
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 };
    try R.check(asset_upload.uploadTexture(core, "__ke_default_normal", 1, 1, &flat_normal_px, flat_normal_px.len, &st.default_normal));
    const black_cube_px = [_]u8{0} ** (4 * 6);
    try R.check(asset_upload.uploadCubemap(core, "__ke_default_cubemap", 1, &black_cube_px, black_cube_px.len, &st.default_cubemap));
    const white_color = abi_math.c.ke_vec4{ .x = 1.0, .y = 1.0, .z = 1.0, .w = 1.0 };
    try R.check(asset_upload.createMaterial(core, "__ke_white_material", white_color, 0.0, 0.5, .{ .bits = abi_render_handles.c.KE_HANDLE_NONE }, .{ .bits = abi_render_handles.c.KE_HANDLE_NONE }, abi_render_handles.c.KE_ALPHA_MODE_OPAQUE, 0.5, 1.5, 0.05, null, &st.white_material));

    st.api = core;
    try st.blit.prepare(core, st.binder);
}

const testing = std.testing;

fn deadFrame(state: *CoreState) abi_render.c.ke_render_service {
    state.frame_live = false;
    var core = std.mem.zeroes(abi_render.c.ke_render_service);
    core.handle = state;
    return core;
}

test {
    _ = slot_map;
    _ = frame_globals;
}

test "a frame that never began submits no upload and ends without presenting anything" {
    var state: CoreState = undefined;
    var core = deadFrame(&state);

    frame_lifecycle.submitUploads(&core);
    try testing.expectEqual(R.ok, frame_lifecycle.endFrame(&core));
}

const zsub = @import("zsub");

/// The device, its command records and the binder a service runs on in a test, with what
/// the recorded commands carried: the latest labels and load ops, and running totals.
const Gpu = struct {
    dev: zsub.ForWith(abi_render_gpu.c.ke_gpu_device, .{ .history = 2 * stress_threads * stress_keys }),
    encoder: zsub.For(abi_render_gpu.c.ke_gpu_command_encoder),
    render_pass: zsub.For(abi_render_gpu.c.ke_gpu_render_pass),
    compute_pass: zsub.For(abi_render_gpu.c.ke_gpu_compute_pass),
    command_buffer: zsub.For(abi_render_gpu.c.ke_gpu_command_buffer),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    pipelines: std.atomic.Value(u64),
    texture_label: [*c]const u8,
    texture_view_label: [*c]const u8,
    render_pass_label: [*c]const u8,
    render_passes: u32,
    color_load: abi_render_gpu.c.ke_gpu_load_op,
    depth_load: ?abi_render_gpu.c.ke_gpu_load_op,
    compute_pass_label: [*c]const u8,
    debug_group_label: [*c]const u8,
    submitted: u32,
    buffer_writes: u32,
    bytes_written: usize,

    fn init(self: *Gpu) !void {
        self.pipelines = .init(1 << 32);
        self.texture_label = null;
        self.texture_view_label = null;
        self.render_pass_label = null;
        self.render_passes = 0;
        self.color_load = 0;
        self.depth_load = null;
        self.compute_pass_label = null;
        self.debug_group_label = null;
        self.submitted = 0;
        self.buffer_writes = 0;
        self.bytes_written = 0;
        try self.render_pass.init();
        try self.compute_pass.init();
        _ = self.compute_pass.when(.push_debug_group).doesWith(self, pushDebugGroup);
        try self.command_buffer.init();
        try self.encoder.init();
        _ = self.encoder.when(.begin_render_pass).doesWith(self, beginRenderPass);
        _ = self.encoder.when(.begin_compute_pass).doesWith(self, beginComputePass);
        _ = self.encoder.when(.finish).writes(1, .{ .ref = self.command_buffer.api(), .destroy = &destroyCommandBuffer });
        try self.dev.init();
        inline for (.{ .create_buffer, .create_bind_group_layout, .create_bind_group, .create_compute_pipeline, .create_render_pipeline, .create_sampler, .create_shader_module, .create_texture }) |slot| _ = self.dev.when(slot).writesFresh(2);
        _ = self.dev.when(.create_texture_view).writesFresh(3).doesWith(self, createTextureView);
        _ = self.dev.when(.create_texture).doesWith(self, createTexture);
        _ = self.dev.when(.create_command_encoder).writes(2, .{ .ref = self.encoder.api(), .destroy = &destroyEncoder });
        _ = self.dev.when(.create_render_pipeline_async).doesWith(self, createRenderPipelineAsync);
        _ = self.dev.when(.queue_submit).doesWith(self, queueSubmit);
        _ = self.dev.when(.write_buffer).doesWith(self, writeBuffer);
        _ = self.dev.when(.get_default_queue).returns(1);
        _ = self.dev.when(.shader_language).returns(abi_render_gpu.c.KE_GPU_SHADER_LANG_WGSL);
        _ = self.dev.when(.get_ndc_convention).returns(.{ .z_zero_to_one = true, .y_flip = true });
        try self.binder.init();
        inline for (.{ .create_shader_layout, .create_material }) |slot| _ = self.binder.when(slot).writesFresh(2);
        _ = self.binder.when(.create_set).writesFresh(6);
    }

    fn deinit(self: *Gpu) void {
        self.binder.deinit();
        self.dev.deinit();
        self.encoder.deinit();
        self.command_buffer.deinit();
        self.compute_pass.deinit();
        self.render_pass.deinit();
    }

    fn expectReleased(self: *Gpu) !void {
        const gpu_handle = zsub.argIsNot(1, abi_render_gpu.c.KE_GPU_INVALID_HANDLE);
        try self.dev.received(.destroy_buffer).where(gpu_handle).sameAs(self.dev.received(.create_buffer));
        try self.dev.received(.destroy_bind_group_layout).where(gpu_handle).sameAs(self.dev.received(.create_bind_group_layout));
        try self.dev.received(.destroy_bind_group).where(gpu_handle).sameAs(self.dev.received(.create_bind_group));
        try self.dev.received(.destroy_compute_pipeline).where(gpu_handle).sameAs(self.dev.received(.create_compute_pipeline));
        try self.dev.received(.destroy_sampler).where(gpu_handle).sameAs(self.dev.received(.create_sampler));
        try self.dev.received(.destroy_shader_module).where(gpu_handle).sameAs(self.dev.received(.create_shader_module));
        try self.dev.received(.destroy_texture).where(gpu_handle).sameAs(self.dev.received(.create_texture));
        try self.dev.received(.destroy_texture_view).where(gpu_handle).sameAs(self.dev.received(.create_texture_view));
        const binding = zsub.argIsNot(1, abi_render_gpu.c.KE_RENDER_BINDING_INVALID);
        try self.binder.received(.destroy_shader_layout).where(binding).sameAs(self.binder.received(.create_shader_layout));
        try self.binder.received(.destroy_set).where(binding).sameAs(self.binder.received(.create_set));
        try self.binder.received(.destroy_material).where(binding).sameAs(self.binder.received(.create_material));
        const pipelines = self.dev.received(.create_render_pipeline).calls + self.dev.received(.create_render_pipeline_async).calls;
        try self.dev.received(.destroy_pipeline).where(gpu_handle).times(pipelines);
    }

    fn beginRenderPass(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_command_encoder).Args(.begin_render_pass)) ?*abi_render_gpu.c.ke_gpu_render_pass {
        const p = args[1].?;
        self.render_pass_label = p.label;
        self.render_passes += 1;
        self.color_load = if (p.color_attachment_count > 0) p.color_attachments.?[0].load_op else 0;
        self.depth_load = if (p.depth_stencil_attachment) |d| d.depth_load_op else null;
        return self.render_pass.api();
    }

    fn beginComputePass(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_command_encoder).Args(.begin_compute_pass)) ?*abi_render_gpu.c.ke_gpu_compute_pass {
        self.compute_pass_label = if (args[1]) |p| p.label else null;
        return self.compute_pass.api();
    }

    fn pushDebugGroup(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_compute_pass).Args(.push_debug_group)) void {
        self.debug_group_label = args[1];
    }

    fn debugGroupsOpen(self: *Gpu) i64 {
        return @as(i64, self.compute_pass.received(.push_debug_group).calls) - self.compute_pass.received(.pop_debug_group).calls;
    }

    fn createTexture(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_device).Args(.create_texture)) abi_result.c.ke_result {
        self.texture_label = args[1].?.label;
        return abi_result.c.KE_OK;
    }

    fn createTextureView(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_device).Args(.create_texture_view)) abi_result.c.ke_result {
        self.texture_view_label = args[2].?.label;
        return abi_result.c.KE_OK;
    }

    fn createRenderPipelineAsync(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_device).Args(.create_render_pipeline_async)) void {
        if (args[2]) |ready| ready(R.ok, self.pipelines.fetchAdd(1, .monotonic), args[3]);
    }

    fn queueSubmit(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_device).Args(.queue_submit)) void {
        self.submitted += args[3];
    }

    fn writeBuffer(self: *Gpu, args: zsub.For(abi_render_gpu.c.ke_gpu_device).Args(.write_buffer)) void {
        self.buffer_writes += 1;
        self.bytes_written += args[4];
    }

    fn destroyEncoder(_: ?*abi_render_gpu.c.ke_gpu_command_encoder) callconv(.c) void {}

    fn destroyCommandBuffer(_: ?*abi_render_gpu.c.ke_gpu_command_buffer) callconv(.c) void {}
};

/// Fake render target. `acquired` is a flag set by `acquire`, not a count, and
/// `presented` is the only tally kept.
const Target = struct {
    vtable: abi_render_gpu.c.ke_gpu_render_target,
    acquired: bool,
    presented: u32,
    width: u32,
    height: u32,

    pub fn init(self: *Target) void {
        self.* = .{ .vtable = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_target), .acquired = false, .presented = 0, .width = 1, .height = 1 };
        self.vtable.handle = self;
        self.vtable.acquire = &acquire;
        self.vtable.present = &present;
        self.vtable.size = &size;
        self.vtable.format = &format;
    }

    pub fn api(self: *Target) *abi_render_gpu.c.ke_gpu_render_target {
        return &self.vtable;
    }

    fn of(self: ?*abi_render_gpu.c.ke_gpu_render_target) *Target {
        return @ptrCast(@alignCast(self.?.handle));
    }

    /// Repeated acquires are not counted: `acquired` is a flag.
    fn acquire(self: ?*abi_render_gpu.c.ke_gpu_render_target, out: [*c]abi_asset_resolver.c.ke_gpu_texture_view) callconv(.c) abi_result.c.ke_result {
        of(self).acquired = true;
        out.* = 1;
        return abi_result.c.KE_OK;
    }

    /// Fails as an invalid argument and leaves `presented` alone unless an acquire came first.
    fn present(self: ?*abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_result.c.ke_result {
        const t = of(self);
        if (!t.acquired) return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
        t.acquired = false;
        t.presented += 1;
        return abi_result.c.KE_OK;
    }

    fn size(self: ?*abi_render_gpu.c.ke_gpu_render_target, out_w: [*c]u32, out_h: [*c]u32) callconv(.c) void {
        if (out_w != null) out_w.* = of(self).width;
        if (out_h != null) out_h.* = of(self).height;
    }

    fn format(_: ?*abi_render_gpu.c.ke_gpu_render_target) callconv(.c) abi_render_gpu.c.ke_gpu_texture_format {
        return abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    }
};

fn serviceOf(device: ?*abi_render_gpu.c.ke_gpu_device, target: ?*abi_render_gpu.c.ke_gpu_render_target, io: ?*abi_io.c.ke_io, binder: ?*abi_render_gpu.c.ke_render_resource_binder, shader_dir: [*c]const u8) abi_render.c.ke_render_service_handle {
    var h: abi_render.c.ke_render_service_handle = .{ .ref = null, .destroy = null };
    _ = ke_render_service_create(device, target, io, binder, shader_dir, &h);
    return h;
}

var empty_shader: [1]u8 = .{0};
var shader_request: u8 = 0;

fn readEmpty(args: zsub.For(abi_io.c.ke_io).Args(.read_file)) abi_result.c.ke_result {
    args[2].?.* = @ptrCast(&shader_request);
    return R.ok;
}

fn waitEmpty(args: zsub.For(abi_io.c.ke_io).Args(.wait)) abi_result.c.ke_result {
    if (args[2]) |out| {
        out.* = std.mem.zeroes(abi_io.c.ke_io_result);
        out.bytes = &empty_shader;
    }
    return R.ok;
}

/// A substitute io under a shader directory, giving every shader the service reads as empty.
const ShaderDir = struct {
    io: zsub.For(abi_io.c.ke_io),

    fn init(self: *ShaderDir) !void {
        try self.io.init();
        _ = self.io.when(.read_file).does(readEmpty);
        _ = self.io.when(.wait).does(waitEmpty);
    }

    fn path(_: *ShaderDir) [*:0]const u8 {
        return "shaders";
    }

    fn api(self: *ShaderDir) *abi_io.c.ke_io {
        return self.io.api();
    }

    fn deinit(self: *ShaderDir) void {
        self.io.deinit();
    }
};

test "creating and destroying the render service leaves no block allocated and no GPU resource live" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

var shader_wait_refused = false;

fn waitUnlessRefused(args: zsub.For(abi_io.c.ke_io).Args(.wait)) abi_result.c.ke_result {
    if (shader_wait_refused) return R.code(error.NotSupported);
    return waitEmpty(args);
}

test "a shader read the calling thread may not wait for is pending until a later load collects it" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    _ = sd.io.when(.wait).does(waitUnlessRefused);
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;

    var module: abi_asset_resolver.c.ke_gpu_shader_module = undefined;
    shader_wait_refused = true;
    try testing.expectError(error.Pending, R.check(svc.*.load_shader.?(svc, "standard.forward", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &module)));
    try testing.expectError(error.Pending, R.check(svc.*.load_shader.?(svc, "standard.forward", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &module)));
    shader_wait_refused = false;
    try R.check(svc.*.load_shader.?(svc, "standard.forward", abi_render_gpu.c.KE_GPU_SHADER_STAGE_VERTEX, &module));
    try testing.expect(module != abi_render_gpu.c.KE_GPU_INVALID_HANDLE);

    h.destroy.?(svc);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a render service created without a render target is refused and leaves nothing behind" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var h: abi_render.c.ke_render_service_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_service_create(gpu.dev.api(), null, sd.api(), gpu.binder.api(), sd.path(), &h)));
    try testing.expect(h.ref == null);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a frame acquires the render target, hands out its view and presents it once at its end" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_texture_format, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), svc.*.backbuffer_format.?(svc));
    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(svc.*.begin_frame.?(svc, &view));
    try testing.expect(target.acquired);
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_gpu_texture_view, 1), view);
    try R.check(svc.*.end_frame.?(svc));
    try testing.expectEqual(@as(u32, 1), target.presented);
    try testing.expectEqual(R.ok, svc.*.end_frame.?(svc));
    try testing.expectEqual(@as(u32, 1), target.presented);
}

test "uploads beyond the first frame's records and arena are all written when submitted, and the next frame needs no spill" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;

    const upload_count = first_upload_records + 100;
    var word: u32 = 7;
    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(svc.*.begin_frame.?(svc, &view));
    for (0..upload_count) |_| svc.*.upload.?(svc, 1, 0, &word, @sizeOf(u32));
    const big = try heap.gpa.alloc(u8, first_upload_arena);
    svc.*.upload.?(svc, 1, 0, big.ptr, big.len);
    const big_len = big.len;
    heap.gpa.free(big);
    try testing.expectEqual(@as(u32, 0), gpu.buffer_writes);
    svc.*.submit_uploads.?(svc);
    _ = svc.*.end_frame.?(svc);
    try testing.expectEqual(@as(u32, upload_count + 1), gpu.buffer_writes);
    try testing.expectEqual(upload_count * @sizeOf(u32) + big_len, gpu.bytes_written);

    const core = coreOf(svc);
    try testing.expect(core.upload_records.len >= upload_count + 1);
    try testing.expect(core.upload_arena.len >= upload_count * @sizeOf(u32) + big_len);

    h.destroy.?(svc);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a blit draws its source over the whole of the render pass it is given, in the target's format" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    var view: abi_asset_resolver.c.ke_gpu_texture_view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE;
    try R.check(svc.*.begin_frame.?(svc, &view));
    svc.*.blit.?(svc, gpu.render_pass.api(), 7, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_BGRA8_UNORM);
    try gpu.render_pass.received(.draw).where(zsub.argIs(1, @as(u32, 3))).times(1);
    try gpu.binder.received(.create_set).times(1);
    _ = svc.*.end_frame.?(svc);
    h.destroy.?(svc);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a render service created without a shader directory is refused and leaves nothing behind" {
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), null);
    try testing.expect(h.ref == null);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a render service created without a config is refused and leaves nothing behind" {
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var h: abi_render.c.ke_render_service_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_service_create(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), null, &h));
    try testing.expect(h.ref == null);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

const stress_keys = 64;
const stress_threads = 8;
const stress_rounds = 4;

const Stress = struct {
    svc: *abi_render.c.ke_render_service,
    params: *[stress_keys]abi_render_gpu.c.ke_gpu_render_pipeline_params,

    fn run(self: *const Stress) void {
        for (0..stress_rounds) |_| {
            for (self.params) |*p| _ = pipeline_cache.getOrCreatePipeline(self.svc, p);
        }
    }
};

test "pipelines requested from several threads at once settle on one answer per key and leak nothing" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    try testing.expect(h.ref != null);

    var params: [stress_keys]abi_render_gpu.c.ke_gpu_render_pipeline_params = undefined;
    for (&params, 0..) |*p, i| {
        p.* = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
        p.vertex_module = i + 1;
        p.fragment_module = i + 1000;
        p.color_target_count = 1;
    }

    const stress = Stress{ .svc = h.ref.?, .params = &params };
    var threads: [stress_threads]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Stress.run, .{&stress});
    for (threads) |t| t.join();

    for (&params) |*p| {
        const first = pipeline_cache.getOrCreatePipeline(h.ref, p);
        try testing.expect(first != abi_render_gpu.c.KE_GPU_INVALID_HANDLE);
        try testing.expectEqual(first, pipeline_cache.getOrCreatePipeline(h.ref, p));
    }

    h.destroy.?(h.ref);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a pipeline is answered with its fallback first and with the compiled one afterwards" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    try testing.expect(h.ref != null);

    var p = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
    p.vertex_module = 5;
    p.fragment_module = 6;
    p.color_target_count = 1;

    const fallback = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    const compiled = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    try testing.expect(fallback != abi_render_gpu.c.KE_GPU_INVALID_HANDLE);
    try testing.expect(compiled != fallback);
    try testing.expectEqual(compiled, pipeline_cache.getOrCreatePipeline(h.ref, &p));

    h.destroy.?(h.ref);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a pipeline is keyed by its vertex layout's content, not by where the layout lives" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), sd.api(), gpu.binder.api(), sd.path());
    try testing.expect(h.ref != null);

    const attrs = [_]abi_render_gpu.c.ke_gpu_vertex_attribute{.{ .shader_location = 0, .format = 0, .offset = 0 }};
    var first_layout = [_]abi_render_gpu.c.ke_gpu_vertex_buffer_layout{.{ .stride = 12, .step_mode = 0, .attribute_count = 1, .attributes = &attrs }};
    var copy_layout = first_layout;

    var p = std.mem.zeroes(abi_render_gpu.c.ke_gpu_render_pipeline_params);
    p.vertex_module = 5;
    p.fragment_module = 6;
    p.color_target_count = 1;
    p.vertex_buffer_count = 1;

    p.vertex_buffers = &first_layout;
    _ = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    const from_first = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    p.vertex_buffers = &copy_layout;
    try testing.expectEqual(from_first, pipeline_cache.getOrCreatePipeline(h.ref, &p));

    first_layout[0].stride = 16;
    p.vertex_buffers = &first_layout;
    try testing.expect(pipeline_cache.getOrCreatePipeline(h.ref, &p) != from_first);

    h.destroy.?(h.ref);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}
