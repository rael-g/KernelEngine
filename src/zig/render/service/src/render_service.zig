//! The root of the render service plugin: the state every file of the plugin works on and the one
//! factory that builds it and fills the `ke_render_service` vtable.

const abi_render_contract = @import("abi_render_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_handles = @import("abi_render_handles");
const std = @import("std");
const FrameLog = @import("frame_log.zig").FrameLog;

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_service").logFn };

pub const abi_ecs = @import("abi_ecs");
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

const resource_table = @import("resource_table.zig");
const blit_mod = @import("blit.zig");
const frame_chain = @import("frame_chain.zig");
const pass_recording = @import("pass_recording.zig");
const frame_lifecycle = @import("frame_lifecycle.zig");
const asset_upload = @import("asset_upload.zig");
const pipeline_cache = @import("pipeline_cache.zig");
const slot_map = @import("slot_map.zig");
const shader_loader = @import("shader_loader.zig");
const frame_globals = @import("frame_globals.zig");

const first_passes = 64;
pub const MAX_COLOR_ATTACH = 8;
pub const first_upload_records = 4096;
const first_resources = 16;
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

/// One named entry of `resources`. The fields from `buffer` on keep their defaults unless an import
/// sets them: `importBuffer` sets the buffer and its size.
/// One named entry of the table. `name` is a copy the table owns, freed with the table.
pub const Resource = struct {
    name: [*:0]const u8,
    cid: abi_asset_resolver.c.ke_component_id,
    format: abi_render_gpu.c.ke_gpu_texture_format,
    texture: abi_asset_resolver.c.ke_gpu_texture,
    view: abi_asset_resolver.c.ke_gpu_texture_view,
    is_backbuffer: bool,
    is_transient: bool,
    clear_value: [4]f32,
    relative: bool = false,
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    buffer: abi_asset_resolver.c.ke_gpu_buffer = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
    buffer_size: u64 = 0,
};

/// The `?u32` labels are offsets into the `labels` of the record that holds the command, not
/// pointers. They are null when no text was stored.
pub const ComputeCmd = union(enum) {
    set_pipeline: abi_asset_resolver.c.ke_gpu_pipeline,
    set_bind_group: struct { index: u32, bg: abi_asset_resolver.c.ke_gpu_bind_group, first_offset: u32, count: u32 },
    dispatch: struct { x: u32, y: u32, z: u32 },
    dispatch_indirect: struct { buf: abi_asset_resolver.c.ke_gpu_buffer, offset: usize },
    push_debug_group: ?u32,
    pop_debug_group,
    insert_debug_marker: ?u32,
};
/// The commands of one compute pass, in the order they were recorded. Labels are copied into
/// `labels` by `storeLabel` and dynamic offsets into `offsets`, so a command never keeps a pointer
/// the caller owns.
pub const ComputeRecord = struct {
    pass: abi_render_gpu.c.ke_gpu_compute_pass,
    cmds: std.ArrayList(ComputeCmd),
    offsets: std.ArrayList(u32),
    pass_label: ?u32,
    labels: std.ArrayList(u8),

    /// Copies the text into `labels`, so the label outlives the caller's buffer. Returns an offset
    /// rather than a pointer, because a later append may move `labels`. Null means nothing was
    /// stored.
    pub const empty: ComputeRecord = .{ .pass = undefined, .cmds = .empty, .offsets = .empty, .pass_label = null, .labels = .empty };

    pub fn deinit(self: *ComputeRecord) void {
        self.labels.deinit(gpa);
        self.cmds.deinit(gpa);
        self.offsets.deinit(gpa);
    }

    pub fn storeLabel(self: *ComputeRecord, text: [*c]const u8) ?u32 {
        if (text == null) return null;
        const offset: u32 = @intCast(self.labels.items.len);
        self.labels.appendSlice(gpa, std.mem.sliceTo(text, 0)) catch return null;
        self.labels.append(gpa, 0) catch {
            self.labels.shrinkRetainingCapacity(offset);
            return null;
        };
        return offset;
    }

    /// The pointer points into `labels`, so it is valid only until the next `storeLabel` on it.
    pub fn label(self: *const ComputeRecord, offset: ?u32) [*c]const u8 {
        const at = offset orelse return null;
        return self.labels.items[at..].ptr;
    }
};

/// The state a render service is built on. `ke_render_service_create` makes it and `destroyCore`
/// frees it. `materialAt` falls
/// back to `white_material` for a handle it does not know. The two upload counters are atomic.
pub const CoreState = struct {
    device: *abi_render_gpu.c.ke_gpu_device,
    ecs: *abi_ecs.c.ke_ecs,
    target: *abi_render_gpu.c.ke_gpu_render_target,
    binder: *abi_render_gpu.c.ke_render_resource_binder,
    queue: abi_asset_resolver.c.ke_gpu_queue,

    resources: std.ArrayList(Resource),

    backbuffer_w: u32,
    backbuffer_h: u32,
    sized_w: u32,
    sized_h: u32,
    resource_generation: u32,
    frame_color: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID,
    frame_depth: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID,

    frame_live: bool,

    ended: FrameLog(EndedPass),
    compute_records: FrameLog(ComputeRecord),

    upload_records: []UploadRecord,
    upload_spill: std.atomic.Value(?*SpilledUpload),
    upload_count: std.atomic.Value(u32),
    upload_arena: []u8,
    upload_arena_offset: std.atomic.Value(usize),

    clear_color: [4]f32,

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

    globals: frame_globals.Globals,
    default_normal: abi_render_handles.c.ke_texture_handle,
    default_cubemap: abi_render_handles.c.ke_texture_handle,
    white_texture_h: abi_render_handles.c.ke_texture_handle,
    white_material: abi_render_handles.c.ke_material_handle,

    ndc: abi_render_gpu.c.ke_ndc_convention,

    pipeline_cache: pipeline_cache.PipelineCache,

    api: [*c]abi_render.c.ke_render_service = null,
    blit: blit_mod.Blit = .{},
    chain: frame_chain.Chain = .{},
    clear_pass: ?abi_render_gpu.c.ke_gpu_command_encoder_handle = null,

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

    /// Scans the entries by name; null when none carries it.
    pub fn findId(self: *CoreState, cid: abi_asset_resolver.c.ke_component_id) ?*Resource {
        if (cid == abi_ecs.c.KE_COMPONENT_INVALID) return null;
        for (self.resources.items) |*r| if (r.cid == cid) return r;
        return null;
    }

    pub fn find(self: *CoreState, name: [*c]const u8) ?*Resource {
        var i: u32 = 0;
        while (i < self.resources.items.len) : (i += 1) {
            if (std.mem.eql(u8, std.mem.span(self.resources.items[i].name), std.mem.span(name))) {
                return &self.resources.items[i];
            }
        }
        return null;
    }
};

/// What a pass context stands for while a pass is open: the state, the pass's declared io, the
/// command encoder it records into and whether it records compute work.
pub const PassState = struct {
    core: *CoreState,
    io: abi_render.c.ke_render_pass_io,
    encoder: abi_render_gpu.c.ke_gpu_command_encoder_handle,
    record: ?*ComputeRecord,
};

/// A pass that ended during the frame: its encoder, and the record replayed on it before it is
/// finished when the pass recorded compute work. The frame submits them in the order they ended.
pub const EndedPass = struct {
    encoder: abi_render_gpu.c.ke_gpu_command_encoder_handle,
    record: ?*ComputeRecord,
    chain: abi_asset_resolver.c.ke_render_chain_link = abi_render.c.KE_RENDER_CHAIN_NONE,
};

/// The state behind a render service vtable.
pub inline fn coreOf(self: [*c]abi_render.c.ke_render_service) *CoreState {
    return @ptrCast(@alignCast(self.*.handle));
}
/// The state behind a pass context.
pub inline fn passOf(self: [*c]abi_render_contract.c.ke_render_pass_ctx) *PassState {
    return @ptrCast(@alignCast(self.*.handle));
}

/// True for the depth and depth-stencil formats.
pub fn isDepthFormat(fmt: abi_render_gpu.c.ke_gpu_texture_format) bool {
    return fmt >= abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

/// The service's `resource_binder` slot.
fn resourceBinder(self: [*c]abi_render.c.ke_render_service) callconv(.c) [*c]abi_render_gpu.c.ke_render_resource_binder {
    if (self == null) return null;
    return coreOf(self).binder;
}

/// The `destroy` of the handle `ke_render_service_create` returns. It flushes the device's pending
/// pipeline compiles first, so no compile still runs against what follows. It then releases the
/// GPU objects of transient resources, the caches and stores, the shared globals and the pipeline
/// cache, and frees the memory the state owns. After it, neither the state nor the
/// vtable is valid.
fn destroyCore(self: [*c]abi_render.c.ke_render_service) callconv(.c) void {
    const st = coreOf(self);
    if (st.device.flush_pipeline_compiles) |flush| flush(st.device);
    st.blit.release(st.binder);
    st.chain.deinit();
    for (st.resources.items) |*r| {
        gpa.free(std.mem.span(r.name));
        if (r.is_transient) {
            if (r.view != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
            if (r.texture != abi_render_gpu.c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        }
    }
    st.material_cache_destroy(st.material_cache);
    st.texture_cache_destroy(st.texture_cache);
    st.mesh_cache_destroy(st.mesh_cache);
    st.shader_cache_destroy(st.shader_cache);
    st.material_store.deinit();
    st.texture_store.deinit();
    st.mesh_store.deinit();
    st.shader_store.deinit();
    st.globals.release(st.device);
    st.pipeline_cache.destroyAll(st.device);
    st.ended.deinit(null);
    st.compute_records.deinit(ComputeRecord.deinit);
    var spilled = st.upload_spill.swap(null, .acquire);
    while (spilled) |n| {
        spilled = n.next;
        gpa.free(n.data);
        gpa.destroy(n);
    }
    gpa.free(st.upload_arena);
    gpa.free(st.upload_records);
    st.resources.deinit(gpa);
    gpa.free(@constCast(st.shader_dir));
    gpa.destroy(st);
    gpa.destroy(@as(*abi_render.c.ke_render_service, @ptrCast(self)));
}

/// Builds the state and the vtable whole, or frees in reverse what it took and fails. The vtable's
/// handle is the state; the shared globals, the default resources, the blit shaders and the frame's
/// color and depth are not made yet.
fn assemble(dev: *abi_render_gpu.c.ke_gpu_device, tgt: *abi_render_gpu.c.ke_gpu_render_target, e: *abi_ecs.c.ke_ecs, bnd: *abi_render_gpu.c.ke_render_resource_binder, shader_dir_span: []const u8, io: *abi_io.c.ke_io) R.Error!*abi_render.c.ke_render_service {
    const st = try gpa.create(CoreState);
    errdefer gpa.destroy(st);
    const upload_arena = try gpa.alloc(u8, first_upload_arena);
    errdefer gpa.free(upload_arena);
    const upload_records = try gpa.alloc(UploadRecord, first_upload_records);
    errdefer gpa.free(upload_records);
    var ended = try FrameLog(EndedPass).init(first_passes, .{ .encoder = .{ .ref = null, .destroy = null }, .record = null });
    errdefer ended.deinit(null);
    var compute_records = try FrameLog(ComputeRecord).init(first_passes, ComputeRecord.empty);
    errdefer compute_records.deinit(ComputeRecord.deinit);
    var resources = try std.ArrayList(Resource).initCapacity(gpa, first_resources);
    errdefer resources.deinit(gpa);
    const shader_dir_owned = try gpa.dupe(u8, shader_dir_span);
    errdefer gpa.free(shader_dir_owned);
    var bb_w: u32 = 0;
    var bb_h: u32 = 0;
    tgt.size.?(tgt, &bb_w, &bb_h);
    st.* = .{
        .device = dev,
        .ecs = e,
        .target = tgt,
        .binder = bnd,
        .queue = dev.get_default_queue.?(dev),
        .resources = resources,
        .backbuffer_w = bb_w,
        .backbuffer_h = bb_h,
        .sized_w = bb_w,
        .sized_h = bb_h,
        .resource_generation = 0,
        .frame_live = false,
        .ended = ended,
        .compute_records = compute_records,
        .upload_records = upload_records,
        .upload_spill = std.atomic.Value(?*SpilledUpload).init(null),
        .upload_count = std.atomic.Value(u32).init(0),
        .upload_arena = upload_arena,
        .upload_arena_offset = std.atomic.Value(usize).init(0),
        .clear_color = .{ 0, 0, 0, 0 },
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

    var bb_cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_params{ .name = "backbuffer", .size = 0, .alignment = 0, .fields = null, .field_count = 0 }, &bb_cid));
    const bb_name = try gpa.dupeZ(u8, "backbuffer");
    errdefer gpa.free(bb_name);
    st.resources.appendAssumeCapacity(.{
        .name = bb_name.ptr,
        .cid = bb_cid,
        .format = tgt.format.?(tgt),
        .texture = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
        .view = abi_render_gpu.c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = true,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    });

    const core = try gpa.create(abi_render.c.ke_render_service);
    core.* = .{
        .handle = st,
        .declare = resource_table.declare,
        .import_texture = resource_table.importTexture,
        .import_tag = resource_table.importTag,
        .import_buffer = resource_table.importBuffer,
        .frame_color = resource_table.frameColor,
        .frame_depth = resource_table.frameDepth,
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
        .material_binding = asset_upload.materialBinding,
        .material_alpha_mode = asset_upload.materialAlphaMode,
        .material_alpha_cutoff = asset_upload.materialAlphaCutoff,
        .upload_cubemap = asset_upload.uploadCubemap,
        .texture_view = asset_upload.textureView,
        .resource_view = resource_table.resourceView,
        .resource_texture = resource_table.resourceTexture,
        .resource_format = resource_table.resourceFormat,
        .resource_buffer = resource_table.resourceBuffer,
        .resource_buffer_size = resource_table.resourceBufferSize,
        .backbuffer_size = resource_table.backbufferSize,
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
        .backbuffer_format = resource_table.backbufferFormat,
        .resource_generation = resource_table.resourceGeneration,
        .join_chain = frame_chain.joinChain,
        .leave_chain = frame_chain.leaveChain,
        .chain_format = frame_chain.chainFormat,
    };
    return core;
}

fn resourceCache(destroy_fn: abi_resource_cache.c.ke_resource_destroy_func, st: *CoreState) R.Error!abi_resource_cache.c.ke_resource_cache_handle {
    var h: abi_resource_cache.c.ke_resource_cache_handle = undefined;
    try R.check(abi_resource_cache_default_factory.c.ke_resource_cache_create(&abi_resource_cache.c.ke_resource_cache_params{ .destroy_fn = destroy_fn, .destroy_ctx = st }, &h));
    return h;
}

/// The factory of the render service, applying `config` as given. It builds in an order its steps
/// depend on: the target's size and the device's queue and NDC convention, then the resource caches,
/// each given its destroy function and the state as context, then the "backbuffer" entry of
/// `resources`, then the vtable, then the shared globals, which it gives the binder. The default
/// resources, the "blit" shaders and the frame's color and depth come last because they go through
/// the functions of the vtable just built. `destroyCore` undoes this in reverse and frees the vtable
/// last. A null dependency, config or shader directory, or an invalid format, fails as an invalid
/// argument; a step that fails fails the factory with its code. On success the ref is the new
/// vtable and `destroy` is `destroyCore`.
export fn ke_render_service_create(
    device: ?*abi_render_gpu.c.ke_gpu_device,
    target: ?*abi_render_gpu.c.ke_gpu_render_target,
    ecs: ?*abi_ecs.c.ke_ecs,
    io: ?*abi_io.c.ke_io,
    binder: ?*abi_render_gpu.c.ke_render_resource_binder,
    config: ?*const Config,
    out_service: [*c]abi_render.c.ke_render_service_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_service orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const dev = device orelse return R.code(error.InvalidArgument);
    const tgt = target orelse return R.code(error.InvalidArgument);
    const e = ecs orelse return R.code(error.InvalidArgument);
    const files = io orelse return R.code(error.InvalidArgument);
    const bnd = binder orelse return R.code(error.InvalidArgument);
    const given = config orelse return R.code(error.InvalidArgument);
    const shader_dir = given.shader_dir orelse return R.code(error.InvalidArgument);
    if (given.color_format == abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID or given.depth_format == abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID)
        return R.code(error.InvalidArgument);

    const core = assemble(dev, tgt, e, bnd, std.mem.span(shader_dir), files) catch |err| return R.code(err);
    coreOf(core).clear_color = .{ given.clear_color.x, given.clear_color.y, given.clear_color.z, given.clear_color.w };
    prepare(core, given.color_format, given.depth_format) catch |err| {
        destroyCore(core);
        return R.code(err);
    };
    out.* = .{ .ref = core, .destroy = destroyCore };
    return R.ok;
}

const Config = abi_render_service_factory.c.ke_render_service_config;

fn prepare(core: *abi_render.c.ke_render_service, color_format: abi_render_gpu.c.ke_gpu_texture_format, depth_format: abi_render_gpu.c.ke_gpu_texture_format) R.Error!void {
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
    try frame_chain.prepare(st, core, color_format, depth_format);
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

test "a pass cannot be opened once the frame has no target view to draw into" {
    var state: CoreState = undefined;
    var core = deadFrame(&state);

    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    try testing.expect(pass_recording.beginPass(&core, &io) == null);
}

test "a frame that never began ends without submitting or presenting anything" {
    var state: CoreState = undefined;
    var core = deadFrame(&state);

    try testing.expectEqual(R.ok, frame_lifecycle.endFrame(&core));
}

const zsub = @import("zsub");

/// The device, its command records, the binder and the ecs a service runs on in a test, with what
/// the recorded commands carried: the latest labels and load ops, and running totals.
const Gpu = struct {
    dev: zsub.ForWith(abi_render_gpu.c.ke_gpu_device, .{ .history = 2 * stress_threads * stress_keys }),
    encoder: zsub.For(abi_render_gpu.c.ke_gpu_command_encoder),
    render_pass: zsub.For(abi_render_gpu.c.ke_gpu_render_pass),
    compute_pass: zsub.For(abi_render_gpu.c.ke_gpu_compute_pass),
    command_buffer: zsub.For(abi_render_gpu.c.ke_gpu_command_buffer),
    binder: zsub.For(abi_render_gpu.c.ke_render_resource_binder),
    ecs: zsub.For(abi_ecs.c.ke_ecs),
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
        try self.ecs.init();
        _ = self.ecs.when(.component_register).writesFresh(2);
        _ = self.ecs.when(.query_register).writesFresh(3);
    }

    fn deinit(self: *Gpu) void {
        self.ecs.deinit();
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

fn serviceOf(device: ?*abi_render_gpu.c.ke_gpu_device, target: ?*abi_render_gpu.c.ke_gpu_render_target, ecs: ?*abi_ecs.c.ke_ecs, io: ?*abi_io.c.ke_io, binder: ?*abi_render_gpu.c.ke_render_resource_binder, shader_dir: [*c]const u8) abi_render.c.ke_render_service_handle {
    var h: abi_render.c.ke_render_service_handle = .{ .ref = null, .destroy = null };
    _ = ke_render_service_create(device, target, ecs, io, binder, &.{ .shader_dir = shader_dir }, &h);
    return h;
}

fn declared(svc: [*c]abi_render.c.ke_render_service, desc: *const abi_render.c.ke_render_resource_params) abi_asset_resolver.c.ke_component_id {
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    _ = svc.*.declare.?(svc, desc, &cid);
    return cid;
}

fn chainLink(svc: [*c]abi_render.c.ke_render_service, stage: abi_render.c.ke_render_stage, mode: abi_render.c.ke_render_chain_mode) abi_asset_resolver.c.ke_render_chain_link {
    var link: abi_asset_resolver.c.ke_render_chain_link = abi_render.c.KE_RENDER_CHAIN_NONE;
    _ = svc.*.join_chain.?(svc, stage, mode, &link);
    return link;
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
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
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
    try testing.expectError(error.InvalidArgument, R.check(ke_render_service_create(gpu.dev.api(), null, gpu.ecs.api(), sd.api(), gpu.binder.api(), &.{ .shader_dir = sd.path() }, &h)));
    try testing.expect(h.ref == null);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a frame acquires the render target as the backbuffer and presents it once at its end" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_texture_format, abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), svc.*.backbuffer_format.?(svc));
    try R.check(svc.*.begin_frame.?(svc));
    try testing.expect(target.acquired);
    try R.check(svc.*.end_frame.?(svc));
    try testing.expectEqual(@as(u32, 1), target.presented);
    try testing.expectEqual(R.ok, svc.*.end_frame.?(svc));
    try testing.expectEqual(@as(u32, 1), target.presented);
}

test "a target declared relative to the backbuffer is recreated when the backbuffer changes size" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;

    var desc = std.mem.zeroes(abi_render.c.ke_render_resource_params);
    desc.name = "hdr";
    desc.format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    desc.size_mode = abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    const hdr = declared(svc, &desc);
    const first = svc.*.resource_view.?(svc, hdr);

    try R.check(svc.*.begin_frame.?(svc));
    _ = svc.*.end_frame.?(svc);
    try testing.expectEqual(first, svc.*.resource_view.?(svc, hdr));
    try testing.expectEqual(@as(u32, 0), svc.*.resource_generation.?(svc));

    target.width = 640;
    target.height = 360;
    try R.check(svc.*.begin_frame.?(svc));
    _ = svc.*.end_frame.?(svc);
    try testing.expect(svc.*.resource_view.?(svc, hdr) != first);
    try testing.expectEqual(@as(u32, 1), svc.*.resource_generation.?(svc));

    h.destroy.?(svc);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "uploads beyond the first frame's records and arena are all written, and the next frame needs no spill" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;

    const upload_count = first_upload_records + 100;
    var word: u32 = 7;
    try R.check(svc.*.begin_frame.?(svc));
    for (0..upload_count) |_| svc.*.upload.?(svc, 1, 0, &word, @sizeOf(u32));
    const big = try heap.gpa.alloc(u8, first_upload_arena);
    svc.*.upload.?(svc, 1, 0, big.ptr, big.len);
    const big_len = big.len;
    heap.gpa.free(big);
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

test "a frame with more passes than the first frame's log submits every one, and the next frame needs no spill" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;

    const pass_count = first_passes + 36;
    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.name = "render.cull";
    try R.check(svc.*.begin_frame.?(svc));
    for (0..pass_count) |_| {
        const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
        const cp = pass.*.begin_compute.?(pass) orelse return error.TestUnexpectedResult;
        cp.*.end.?(cp);
        svc.*.end_pass.?(svc, pass);
    }
    try R.check(svc.*.end_frame.?(svc));
    try testing.expectEqual(@as(u32, pass_count + 2), gpu.submitted);

    try R.check(svc.*.begin_frame.?(svc));
    const core = coreOf(svc);
    try testing.expect(core.ended.items.len >= pass_count);
    try testing.expect(core.compute_records.items.len >= pass_count);
    try R.check(svc.*.end_frame.?(svc));

    h.destroy.?(svc);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a declared resource's texture and view carry the name it was declared under" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    var desc = std.mem.zeroes(abi_render.c.ke_render_resource_params);
    desc.name = "hdr_color";
    desc.format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    desc.size_mode = abi_render.c.KE_RENDER_SIZE_ABSOLUTE;
    desc.width = 4;
    desc.height = 4;
    _ = declared(svc, &desc);

    try testing.expectEqualStrings("hdr_color", std.mem.span(gpu.texture_label));
    try testing.expectEqualStrings("hdr_color", std.mem.span(gpu.texture_view_label));
}

test "a render pass is opened under the name its pass declared" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    const writes = [_]abi_asset_resolver.c.ke_component_id{svc.*.frame_depth.?(svc)};
    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.name = "render.named";
    io.writes = &writes;
    io.writes_count = 1;

    try R.check(svc.*.begin_frame.?(svc));
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    const rp = pass.*.begin_render.?(pass);
    try testing.expectEqualStrings("render.named", std.mem.span(gpu.render_pass_label));
    rp.?.end.?(rp);
    svc.*.end_pass.?(svc, pass);
    try R.check(svc.*.end_frame.?(svc));
}

/// A service over substitutes with a source and a destination color resource declared; `begin`
/// begins a frame, which `deinit` ends.
const PassHarness = struct {
    sd: ShaderDir,
    gpu: Gpu,
    target: Target,
    h: abi_render.c.ke_render_service_handle,
    src: abi_asset_resolver.c.ke_component_id,
    dst: abi_asset_resolver.c.ke_component_id,

    fn init(self: *PassHarness) !void {
        try self.sd.init();
        try self.gpu.init();
        self.target.init();
        self.h = serviceOf(self.gpu.dev.api(), self.target.api(), self.gpu.ecs.api(), self.sd.api(), self.gpu.binder.api(), self.sd.path());
        const svc = self.h.ref orelse return error.TestUnexpectedResult;
        for ([_][*:0]const u8{ "src", "dst" }, [_]*abi_asset_resolver.c.ke_component_id{ &self.src, &self.dst }) |name, out| {
            var desc = std.mem.zeroes(abi_render.c.ke_render_resource_params);
            desc.name = name;
            desc.format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
            desc.size_mode = abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
            desc.scale_x = 1.0;
            desc.scale_y = 1.0;
            out.* = declared(svc, &desc);
            try testing.expect(out.* != abi_ecs.c.KE_COMPONENT_INVALID);
        }
    }

    fn begin(self: *PassHarness) !void {
        const svc = self.h.ref.?;
        try R.check(svc.*.begin_frame.?(svc));
    }

    fn run(self: *PassHarness, io: *const abi_render.c.ke_render_pass_io) !void {
        const svc = self.h.ref.?;
        self.gpu.render_passes = 0;
        const pass = svc.*.begin_pass.?(svc, io) orelse return error.TestUnexpectedResult;
        const rp = pass.*.begin_render.?(pass);
        rp.?.end.?(rp);
        svc.*.end_pass.?(svc, pass);
    }

    fn deinit(self: *PassHarness) void {
        const svc = self.h.ref.?;
        _ = svc.*.end_frame.?(svc);
        self.h.destroy.?(svc);
        self.gpu.deinit();
        self.sd.deinit();
    }
};

fn joined(ph: *PassHarness, stage: abi_render.c.ke_render_stage, mode: abi_render.c.ke_render_chain_mode) !abi_render.c.ke_render_pass_io {
    const svc = ph.h.ref.?;
    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.name = "render.link";
    io.chain = chainLink(svc, stage, mode);
    try testing.expect(io.chain != abi_render.c.KE_RENDER_CHAIN_NONE);
    return io;
}

test "a pass drawing over the frame's color loads it in a single render pass" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const io = try joined(&ph, abi_render.c.KE_RENDER_STAGE_OPAQUE, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER);
    try ph.begin();
    try ph.run(&io);

    try testing.expectEqual(@as(u32, 1), ph.gpu.render_passes);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_load_op, abi_render_gpu.c.KE_GPU_LOAD_OP_LOAD), ph.gpu.color_load);
}

test "a pass that samples the frame's color draws over a copy of it, made first" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const io = try joined(&ph, abi_render.c.KE_RENDER_STAGE_TRANSPARENT, abi_render.c.KE_RENDER_CHAIN_SAMPLE_OVER);
    try ph.begin();
    try ph.run(&io);

    try testing.expectEqual(@as(u32, 2), ph.gpu.render_passes);
    try testing.expectEqualStrings("render.link", std.mem.span(ph.gpu.render_pass_label));
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_load_op, abi_render_gpu.c.KE_GPU_LOAD_OP_LOAD), ph.gpu.color_load);
}

test "a pass that replaces the frame's color clears the new one and samples the old" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const svc = ph.h.ref.?;
    const io = try joined(&ph, abi_render.c.KE_RENDER_STAGE_TONEMAP, abi_render.c.KE_RENDER_CHAIN_REPLACE);
    try ph.begin();
    ph.gpu.render_passes = 0;
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    const source = pass.*.color_source.?(pass);
    const rp = pass.*.begin_render.?(pass);
    rp.?.end.?(rp);
    svc.*.end_pass.?(svc, pass);

    try testing.expect(source != abi_render_gpu.c.KE_GPU_INVALID_HANDLE);
    try testing.expectEqual(@as(u32, 1), ph.gpu.render_passes);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_load_op, abi_render_gpu.c.KE_GPU_LOAD_OP_CLEAR), ph.gpu.color_load);
}

test "a pass outside the chain clears its write and samples no color" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    try ph.begin();
    const svc = ph.h.ref.?;

    const writes = [_]abi_asset_resolver.c.ke_component_id{ph.dst};
    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.writes = &writes;
    io.writes_count = 1;
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    try testing.expectEqual(@as(abi_asset_resolver.c.ke_gpu_texture_view, abi_render_gpu.c.KE_GPU_INVALID_HANDLE), pass.*.color_source.?(pass));
    ph.gpu.render_passes = 0;
    const rp = pass.*.begin_render.?(pass);
    rp.?.end.?(rp);
    svc.*.end_pass.?(svc, pass);

    try testing.expectEqual(@as(u32, 1), ph.gpu.render_passes);
    try testing.expectEqual(@as(abi_render_gpu.c.ke_gpu_load_op, abi_render_gpu.c.KE_GPU_LOAD_OP_CLEAR), ph.gpu.color_load);
    try testing.expectEqual(@as(?abi_render_gpu.c.ke_gpu_load_op, null), ph.gpu.depth_load);
}

test "a pass asking for the frame's depth has it attached loaded" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    try ph.begin();

    const writes = [_]abi_asset_resolver.c.ke_component_id{ph.dst};
    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.writes = &writes;
    io.writes_count = 1;
    io.depth = abi_render.c.KE_RENDER_DEPTH_TEST;
    try ph.run(&io);

    try testing.expectEqual(@as(?abi_render_gpu.c.ke_gpu_load_op, abi_render_gpu.c.KE_GPU_LOAD_OP_LOAD), ph.gpu.depth_load);
}

test "the chain runs by stage, and within a stage in the order the passes joined" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const svc = ph.h.ref.?;
    const overlay = chainLink(svc, abi_render.c.KE_RENDER_STAGE_OVERLAY, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER);
    const sky = chainLink(svc, abi_render.c.KE_RENDER_STAGE_SKY, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER);
    const opaque_first = chainLink(svc, abi_render.c.KE_RENDER_STAGE_OPAQUE, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER);
    const opaque_second = chainLink(svc, abi_render.c.KE_RENDER_STAGE_OPAQUE, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER);
    try ph.begin();

    var order: [4]abi_asset_resolver.c.ke_render_chain_link = undefined;
    for (coreOf(svc).chain.links.items, &order) |l, *o| o.* = l.id;
    try testing.expectEqualSlices(abi_asset_resolver.c.ke_render_chain_link, &.{ opaque_first, opaque_second, sky, overlay }, &order);
}

test "a link whose pass recorded nothing still carries the color through it" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const svc = ph.h.ref.?;
    ph.gpu.render_passes = 0;
    try ph.begin();
    try R.check(svc.*.end_frame.?(svc));
    const without = ph.gpu.render_passes;

    _ = try joined(&ph, abi_render.c.KE_RENDER_STAGE_HDR_POST, abi_render.c.KE_RENDER_CHAIN_REPLACE);
    ph.gpu.render_passes = 0;
    try ph.begin();
    try R.check(svc.*.end_frame.?(svc));

    try testing.expectEqual(without + 1, ph.gpu.render_passes);
}

test "joining the chain refuses a stage out of range" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    try ph.begin();
    const svc = ph.h.ref.?;
    var link: abi_asset_resolver.c.ke_render_chain_link = undefined;
    try testing.expectError(error.InvalidArgument, R.check(svc.*.join_chain.?(svc, abi_render.c.KE_RENDER_STAGE_COUNT, abi_render.c.KE_RENDER_CHAIN_DRAW_OVER, &link)));
    try testing.expectEqual(abi_render.c.KE_RENDER_CHAIN_NONE, link);
}

test "declaring a label again declares a resource of its own" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const svc = ph.h.ref.?;

    var desc = std.mem.zeroes(abi_render.c.ke_render_resource_params);
    desc.name = "src";
    desc.format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    desc.size_mode = abi_render.c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    const again = declared(svc, &desc);
    try testing.expect(again != abi_ecs.c.KE_COMPONENT_INVALID);
    try testing.expect(again != ph.src);
}

test "a compute pass replays at the end of the frame under its name and with the debug groups recorded into it" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    var io = std.mem.zeroes(abi_render.c.ke_render_pass_io);
    io.name = "render.cull";

    try R.check(svc.*.begin_frame.?(svc));
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    const cp = pass.*.begin_compute.?(pass);
    var transient = [_:0]u8{ 'b', 'i', 'n' };
    cp.?.push_debug_group.?(cp, &transient);
    transient[0] = 'x';
    cp.?.pop_debug_group.?(cp);
    cp.?.end.?(cp);
    svc.*.end_pass.?(svc, pass);
    try testing.expect(gpu.compute_pass_label == null);
    try R.check(svc.*.end_frame.?(svc));

    try testing.expectEqualStrings("render.cull", std.mem.span(gpu.compute_pass_label));
    try testing.expectEqualStrings("bin", std.mem.span(gpu.debug_group_label));
    try testing.expectEqual(@as(i64, 0), gpu.debugGroupsOpen());
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
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), null);
    try testing.expect(h.ref == null);
    try gpu.expectReleased();
    try heap.expectNoLeaks();
}

test "a render service created without a config or with an invalid format is refused and leaves nothing behind" {
    var gpu: Gpu = undefined;
    try gpu.init();
    defer gpu.deinit();
    var target: Target = undefined;
    target.init();
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var h: abi_render.c.ke_render_service_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_service_create(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), null, &h));
    try testing.expect(h.ref == null);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_service_create(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), &.{ .shader_dir = sd.path(), .color_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID }, &h));
    try testing.expect(h.ref == null);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_render_service_create(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), &.{ .shader_dir = sd.path(), .depth_format = abi_render_gpu.c.KE_GPU_TEXTURE_FORMAT_INVALID }, &h));
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
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
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
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
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
    const h = serviceOf(gpu.dev.api(), target.api(), gpu.ecs.api(), sd.api(), gpu.binder.api(), sd.path());
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
