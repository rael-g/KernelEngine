//! The root of the render service plugin: the state every file of the plugin works on and the one
//! factory that builds it and fills the `ke_render_service` vtable.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const c = @import("c");

const heap = @import("heap");
pub const gpa = heap.gpa;

const resource_table = @import("resource_table.zig");
const blit_mod = @import("blit.zig");
const pass_recording = @import("pass_recording.zig");
const frame_lifecycle = @import("frame_lifecycle.zig");
const asset_upload = @import("asset_upload.zig");
const pipeline_cache = @import("pipeline_cache.zig");
const slot_map = @import("slot_map.zig");
const shader_loader = @import("shader_loader.zig");
const frame_globals = @import("frame_globals.zig");

pub const MAX_CMD_BUFFERS = 64;
pub const MAX_COLOR_ATTACH = 8;
pub const first_upload_records = 4096;
const first_resources = 16;
pub const MAX_SHADER_NAME = 64;
pub const DEFAULT_MATERIAL_SHADER = "standard";
const first_upload_arena = 8 * 1024 * 1024;

/// One buffer write queued during a frame: where it goes on the GPU and the bytes it copies out
/// of the upload arena.
pub const UploadRecord = struct {
    buffer: c.ke_gpu_buffer,
    gpu_offset: u64,
    arena_offset: usize,
    size: usize,
};

/// An upload that found the arena or the records full, in a block of its own, linked onto
/// `upload_spill` by the thread that made it.
pub const SpilledUpload = struct {
    next: ?*SpilledUpload,
    buffer: c.ke_gpu_buffer,
    gpu_offset: u64,
    data: []u8,
};

/// A mesh in `mesh_store`: the vertex and index buffers it owns and the number of indices.
pub const Mesh = struct {
    vbo: c.ke_gpu_buffer,
    ibo: c.ke_gpu_buffer,
    index_count: u32,
};

/// A texture in `texture_store`: the GPU texture it owns and its default view.
pub const Texture = struct {
    tex: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
};

/// A material in `material_store`: what the binder holds for it, its alpha mode and cutoff, the
/// name of its shader, and the albedo and normal textures it samples.
pub const Material = struct {
    binding: c.ke_render_material_binding,
    alpha_mode: c.ke_alpha_mode,
    alpha_cutoff: f32,
    shader: [MAX_SHADER_NAME]u8,
    albedo: c.ke_texture_handle,
    normal: c.ke_texture_handle,
};

/// One named entry of `resources`. The fields from `buffer` on keep their defaults unless an import
/// sets them: `importBuffer` sets the buffer and its size.
/// One named entry of the table. `name` is a copy the table owns, freed with the table.
pub const Resource = struct {
    name: [*:0]const u8,
    cid: c.ke_component_id,
    format: c.ke_gpu_texture_format,
    texture: c.ke_gpu_texture,
    view: c.ke_gpu_texture_view,
    is_backbuffer: bool,
    is_transient: bool,
    clear_value: [4]f32,
    relative: bool = false,
    scale_x: f32 = 1.0,
    scale_y: f32 = 1.0,
    buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    buffer_size: u64 = 0,
};

/// The `?u32` labels are offsets into the `labels` of the record that holds the command, not
/// pointers. They are null when no text was stored.
pub const ComputeCmd = union(enum) {
    set_pipeline: c.ke_gpu_pipeline,
    set_bind_group: struct { index: u32, bg: c.ke_gpu_bind_group, first_offset: u32, count: u32 },
    dispatch: struct { x: u32, y: u32, z: u32 },
    dispatch_indirect: struct { buf: c.ke_gpu_buffer, offset: usize },
    push_debug_group: ?u32,
    pop_debug_group,
    insert_debug_marker: ?u32,
};
/// The commands of one compute pass, in the order they were recorded. Labels are copied into
/// `labels` by `storeLabel` and dynamic offsets into `offsets`, so a command never keeps a pointer
/// the caller owns.
pub const ComputeRecord = struct {
    pass: c.ke_gpu_compute_pass,
    cmds: std.ArrayList(ComputeCmd),
    offsets: std.ArrayList(u32),
    pass_label: ?u32,
    labels: std.ArrayList(u8),

    /// Copies the text into `labels`, so the label outlives the caller's buffer. Returns an offset
    /// rather than a pointer, because a later append may move `labels`. Null means nothing was
    /// stored.
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
    device: *c.ke_gpu_device,
    ecs: *c.ke_ecs,
    target: *c.ke_gpu_render_target,
    binder: *c.ke_render_resource_binder,
    queue: c.ke_gpu_queue,

    resources: std.ArrayList(Resource),

    backbuffer_w: u32,
    backbuffer_h: u32,
    sized_w: u32,
    sized_h: u32,
    resource_generation: u32,

    frame_live: bool,

    ended: [MAX_CMD_BUFFERS]EndedPass,
    ended_count: std.atomic.Value(u32),

    compute_records: [MAX_CMD_BUFFERS]ComputeRecord,
    compute_count: std.atomic.Value(u32),

    upload_records: []UploadRecord,
    upload_spill: std.atomic.Value(?*SpilledUpload),
    upload_count: std.atomic.Value(u32),
    upload_arena: []u8,
    upload_arena_offset: std.atomic.Value(usize),

    clear_color: [4]f32,

    mesh_store: slot_map.SlotMap(Mesh),
    texture_store: slot_map.SlotMap(Texture),
    material_store: slot_map.SlotMap(Material),
    mesh_cache: *c.ke_resource_cache,
    texture_cache: *c.ke_resource_cache,
    material_cache: *c.ke_resource_cache,
    mesh_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    texture_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    material_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,

    shader_store: slot_map.SlotMap(c.ke_gpu_shader_module),
    shader_cache: *c.ke_resource_cache,
    shader_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    shader_dir: []const u8,

    globals: frame_globals.Globals,
    default_normal: c.ke_texture_handle,
    default_cubemap: c.ke_texture_handle,
    white_texture_h: c.ke_texture_handle,
    white_material: c.ke_material_handle,

    ndc: c.ke_ndc_convention,

    pipeline_cache: pipeline_cache.PipelineCache,

    api: [*c]c.ke_render_service = null,
    blit: blit_mod.Blit = .{},

    /// Null when the handle is stale or was never issued.
    pub fn meshAt(self: *CoreState, h: c.ke_mesh_handle) ?*Mesh {
        return self.mesh_store.get(h.bits);
    }

    /// Null when the handle is stale or was never issued.
    pub fn textureAt(self: *CoreState, h: c.ke_texture_handle) ?*Texture {
        return self.texture_store.get(h.bits);
    }

    pub fn materialAt(self: *CoreState, h: c.ke_material_handle) *Material {
        return self.material_store.get(h.bits) orelse
            self.material_store.get(self.white_material.bits).?;
    }

    /// Scans the entries by name; null when none carries it.
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
    io: c.ke_render_pass_io,
    encoder: c.ke_gpu_command_encoder_handle,
    record: ?*ComputeRecord,
};

/// A pass that ended during the frame: its encoder, and the record replayed on it before it is
/// finished when the pass recorded compute work. The frame submits them in the order they ended.
pub const EndedPass = struct {
    encoder: c.ke_gpu_command_encoder_handle,
    record: ?*ComputeRecord,
};

/// The state behind a render service vtable.
pub inline fn coreOf(self: [*c]c.ke_render_service) *CoreState {
    return @alignCast(@ptrCast(self.*.handle));
}
/// The state behind a pass context.
pub inline fn passOf(self: [*c]c.ke_render_pass_ctx) *PassState {
    return @alignCast(@ptrCast(self.*.handle));
}

/// True for the depth and depth-stencil formats.
pub fn isDepthFormat(fmt: c.ke_gpu_texture_format) bool {
    return fmt >= c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

/// The service's `resource_binder` slot.
fn resourceBinder(self: [*c]c.ke_render_service) callconv(.c) [*c]c.ke_render_resource_binder {
    if (self == null) return null;
    return coreOf(self).binder;
}

/// The `destroy` of the handle `ke_render_service_create` returns. It flushes the device's pending
/// pipeline compiles first, so no compile still runs against what follows. It then releases the
/// GPU objects of transient resources, the caches and stores, the shared globals and the pipeline
/// cache, and frees the memory the state owns. After it, neither the state nor the
/// vtable is valid.
fn destroyCore(self: [*c]c.ke_render_service) callconv(.c) void {
    const st = coreOf(self);
    if (st.device.flush_pipeline_compiles) |flush| flush(st.device);
    st.blit.release(st.binder);
    for (st.resources.items) |*r| {
        gpa.free(std.mem.span(r.name));
        if (r.is_transient) {
            if (r.view != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
            if (r.texture != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
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
    for (&st.compute_records) |*r| {
        r.labels.deinit(gpa);
        r.cmds.deinit(gpa);
        r.offsets.deinit(gpa);
    }
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
    gpa.destroy(@as(*c.ke_render_service, @ptrCast(self)));
}

/// The factory of the render service. It builds in an order its steps depend on: the target's size
/// and the device's queue and NDC convention, then the resource caches, each given its destroy
/// function and the state as context, then the "backbuffer" entry of `resources`, then the vtable,
/// then the shared globals, which it gives the binder. The default resources and the "blit" shaders
/// come last because they go through the functions of the vtable just built. `destroyCore` undoes
/// this in reverse and frees the vtable last. A null device or ecs returns a null ref without
/// setting the error. A null target, shader directory or binder sets the invalid-argument error,
/// and blit shaders that cannot be loaded set the loader's error. Any other failure returns a null
/// ref with no error set. On success the ref is the new vtable and `destroy` is
/// `destroyCore`.
export fn ke_render_service_create(device: ?*c.ke_gpu_device, target: ?*c.ke_gpu_render_target, ecs: ?*c.ke_ecs, shader_dir: [*c]const u8, binder: ?*c.ke_render_resource_binder, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_service_handle {
    const dev = device orelse return .{ .ref = null, .destroy = null };
    const tgt = target orelse {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ke_render_service_create: target is required", @src().file, @intCast(@src().line), null);
        return .{ .ref = null, .destroy = null };
    };
    const e = ecs orelse return .{ .ref = null, .destroy = null };
    const shader_dir_span = if (shader_dir != null) std.mem.span(shader_dir) else {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ke_render_service_create: shader_dir is required", @src().file, @intCast(@src().line), null);
        return .{ .ref = null, .destroy = null };
    };
    const bnd = binder orelse {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ke_render_service_create: binder is required", @src().file, @intCast(@src().line), null);
        return .{ .ref = null, .destroy = null };
    };

    const st = gpa.create(CoreState) catch return .{ .ref = null, .destroy = null };
    const upload_arena = gpa.alloc(u8, first_upload_arena) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    const upload_records = gpa.alloc(UploadRecord, first_upload_records) catch {
        gpa.free(upload_arena);
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    var resources = std.ArrayList(Resource).initCapacity(gpa, first_resources) catch {
        gpa.free(upload_records);
        gpa.free(upload_arena);
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    const shader_dir_owned = gpa.dupe(u8, shader_dir_span) catch {
        resources.deinit(gpa);
        gpa.free(upload_records);
        gpa.free(upload_arena);
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
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
        .ended = undefined,
        .ended_count = std.atomic.Value(u32).init(0),
        .compute_records = undefined,
        .compute_count = std.atomic.Value(u32).init(0),
        .upload_records = upload_records,
        .upload_spill = std.atomic.Value(?*SpilledUpload).init(null),
        .upload_count = std.atomic.Value(u32).init(0),
        .upload_arena = upload_arena,
        .upload_arena_offset = std.atomic.Value(usize).init(0),
        .clear_color = .{ 0.10, 0.15, 0.30, 1.0 },
        .mesh_store = slot_map.SlotMap(Mesh).init(gpa),
        .texture_store = slot_map.SlotMap(Texture).init(gpa),
        .material_store = slot_map.SlotMap(Material).init(gpa),
        .mesh_cache = undefined,
        .texture_cache = undefined,
        .material_cache = undefined,
        .mesh_cache_destroy = undefined,
        .texture_cache_destroy = undefined,
        .material_cache_destroy = undefined,
        .shader_store = slot_map.SlotMap(c.ke_gpu_shader_module).init(gpa),
        .shader_cache = undefined,
        .shader_cache_destroy = undefined,
        .shader_dir = shader_dir_owned,
        .globals = .{},
        .default_normal = .{ .bits = c.KE_HANDLE_NONE },
        .default_cubemap = .{ .bits = c.KE_HANDLE_NONE },
        .white_texture_h = .{ .bits = c.KE_HANDLE_NONE },
        .white_material = .{ .bits = c.KE_HANDLE_NONE },
        .ndc = dev.get_ndc_convention.?(dev),
        .pipeline_cache = pipeline_cache.PipelineCache.init(),
    };
    for (&st.compute_records) |*r| {
        r.labels = .empty;
        r.cmds = .empty;
        r.offsets = .empty;
    }

    const mesh_ch = c.ke_resource_cache_create(&c.ke_resource_cache_params{
        .destroy_fn = asset_upload.destroyMeshResource,
        .destroy_ctx = st,
    }, null);
    const tex_ch = c.ke_resource_cache_create(&c.ke_resource_cache_params{
        .destroy_fn = asset_upload.destroyTextureResource,
        .destroy_ctx = st,
    }, null);
    const mat_ch = c.ke_resource_cache_create(&c.ke_resource_cache_params{
        .destroy_fn = asset_upload.destroyMaterialResource,
        .destroy_ctx = st,
    }, null);
    const shader_ch = c.ke_resource_cache_create(&c.ke_resource_cache_params{
        .destroy_fn = shader_loader.destroyShaderResource,
        .destroy_ctx = st,
    }, null);
    if (mesh_ch.ref == null or tex_ch.ref == null or mat_ch.ref == null or shader_ch.ref == null) {
        gpa.free(shader_dir_owned);
        resources.deinit(gpa);
        gpa.free(upload_records);
        gpa.free(upload_arena);
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    }
    st.mesh_cache = mesh_ch.ref.?;
    st.texture_cache = tex_ch.ref.?;
    st.material_cache = mat_ch.ref.?;
    st.shader_cache = shader_ch.ref.?;
    st.mesh_cache_destroy = mesh_ch.destroy.?;
    st.texture_cache_destroy = tex_ch.destroy.?;
    st.material_cache_destroy = mat_ch.destroy.?;
    st.shader_cache_destroy = shader_ch.destroy.?;

    const bb_cid = e.component_register.?(e, "backbuffer", 0, null, 0, null);
    const bb_name = gpa.dupeZ(u8, "backbuffer") catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    st.resources.appendAssumeCapacity(.{
        .name = bb_name.ptr,
        .cid = bb_cid,
        .format = tgt.format.?(tgt),
        .texture = c.KE_GPU_INVALID_HANDLE,
        .view = c.KE_GPU_INVALID_HANDLE,
        .is_backbuffer = true,
        .is_transient = false,
        .clear_value = .{ 0, 0, 0, 0 },
    });

    const core = gpa.create(c.ke_render_service) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    core.* = .{
        .handle = st,
        .declare = resource_table.declare,
        .import_texture = resource_table.importTexture,
        .import_tag = resource_table.importTag,
        .import_buffer = resource_table.importBuffer,
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
    };

    if (!st.globals.create(dev, out_error) or !st.globals.provideTo(bnd, out_error)) {
        destroyCore(core);
        return .{ .ref = null, .destroy = null };
    }
    const white_px = [_]u8{ 255, 255, 255, 255 };
    st.white_texture_h = asset_upload.uploadTexture(core, "__ke_white_texture", 1, 1, &white_px, null);
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 };
    st.default_normal = asset_upload.uploadTexture(core, "__ke_default_normal", 1, 1, &flat_normal_px, null);
    const black_cube_px = [_]u8{0} ** (4 * 6);
    st.default_cubemap = asset_upload.uploadCubemap(core, "__ke_default_cubemap", 1, &black_cube_px, null);
    const white_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    st.white_material = asset_upload.createMaterial(core, "__ke_white_material", &white_color, 0.0, 0.5, .{ .bits = c.KE_HANDLE_NONE }, .{ .bits = c.KE_HANDLE_NONE }, c.KE_ALPHA_MODE_OPAQUE, 0.5, 1.5, 0.05, null, null);

    st.api = core;
    if (!st.blit.prepare(core, st.binder, out_error)) {
        destroyCore(core);
        return .{ .ref = null, .destroy = null };
    }

    return .{ .ref = core, .destroy = destroyCore };
}

const testing = std.testing;

fn deadFrame(state: *CoreState) c.ke_render_service {
    state.frame_live = false;
    var core = std.mem.zeroes(c.ke_render_service);
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

    var io = std.mem.zeroes(c.ke_render_pass_io);
    try testing.expect(pass_recording.beginPass(&core, &io) == null);
}

test "a frame that never began ends without submitting or presenting anything" {
    var state: CoreState = undefined;
    var core = deadFrame(&state);

    try testing.expectEqual(false, frame_lifecycle.endFrame(&core, null));
}

const Stubs = @import("stubs").Stubs(c);

/// A temporary shader directory holding the two "blit" files the service loads when created.
const ShaderDir = struct {
    tmp: std.testing.TmpDir,
    buf: [std.fs.max_path_bytes]u8,

    fn init(self: *ShaderDir) !void {
        self.tmp = std.testing.tmpDir(.{});
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = "blit.vs.wgsl", .data = "" });
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = "blit.fs.wgsl", .data = "" });
        _ = try std.fmt.bufPrintZ(&self.buf, ".zig-cache/tmp/{s}", .{self.tmp.sub_path});
    }

    fn path(self: *ShaderDir) [*:0]const u8 {
        return @ptrCast(&self.buf);
    }

    fn deinit(self: *ShaderDir) void {
        self.tmp.cleanup();
    }
};

test "creating and destroying the render service leaves no block allocated and no GPU resource live" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try testing.expectEqual(@as(i64, 0), binder.live);
    try heap.expectNoLeaks();
}

test "a render service created without a render target is refused and leaves nothing behind" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var err: [*c]c.ke_error = null;
    const h = ke_render_service_create(dev.api(), null, ecs.api(), sd.path(), binder.api(), &err);
    try testing.expect(h.ref == null);
    try testing.expect(err != null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a frame acquires the render target as the backbuffer and presents it once at its end" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);
    try testing.expectEqual(@as(c.ke_gpu_texture_format, c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM), svc.*.backbuffer_format.?(svc));
    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    try testing.expect(target.acquired);
    try testing.expectEqual(true, svc.*.end_frame.?(svc, null));
    try testing.expectEqual(@as(u32, 1), target.presented);
    try testing.expectEqual(false, svc.*.end_frame.?(svc, null));
    try testing.expectEqual(@as(u32, 1), target.presented);
}

test "a target declared relative to the backbuffer is recreated when the backbuffer changes size" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;

    var desc = std.mem.zeroes(c.ke_render_resource_params);
    desc.name = "hdr";
    desc.format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    desc.size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    _ = svc.*.declare.?(svc, &desc, null);
    const first = svc.*.resource_view.?(svc, "hdr");

    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    _ = svc.*.end_frame.?(svc, null);
    try testing.expectEqual(first, svc.*.resource_view.?(svc, "hdr"));
    try testing.expectEqual(@as(u32, 0), svc.*.resource_generation.?(svc));

    target.width = 640;
    target.height = 360;
    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    _ = svc.*.end_frame.?(svc, null);
    try testing.expect(svc.*.resource_view.?(svc, "hdr") != first);
    try testing.expectEqual(@as(u32, 1), svc.*.resource_generation.?(svc));

    h.destroy.?(svc);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "uploads beyond the first frame's records and arena are all written, and the next frame needs no spill" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;

    const upload_count = first_upload_records + 100;
    var word: u32 = 7;
    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    for (0..upload_count) |_| svc.*.upload.?(svc, 1, 0, &word, @sizeOf(u32));
    const big = try heap.gpa.alloc(u8, first_upload_arena);
    svc.*.upload.?(svc, 1, 0, big.ptr, big.len);
    const big_len = big.len;
    heap.gpa.free(big);
    _ = svc.*.end_frame.?(svc, null);
    try testing.expectEqual(@as(u32, upload_count + 1), dev.buffer_writes);
    try testing.expectEqual(upload_count * @sizeOf(u32) + big_len, dev.bytes_written);

    const core = coreOf(svc);
    try testing.expect(core.upload_records.len >= upload_count + 1);
    try testing.expect(core.upload_arena.len >= upload_count * @sizeOf(u32) + big_len);

    h.destroy.?(svc);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a declared resource's texture and view carry the name it was declared under" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    var desc = std.mem.zeroes(c.ke_render_resource_params);
    desc.name = "hdr_color";
    desc.format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    desc.size_mode = c.KE_RENDER_SIZE_ABSOLUTE;
    desc.width = 4;
    desc.height = 4;
    _ = svc.*.declare.?(svc, &desc, null);

    try testing.expectEqualStrings("hdr_color", std.mem.span(dev.texture_label));
    try testing.expectEqualStrings("hdr_color", std.mem.span(dev.texture_view_label));
}

test "a render pass is opened under the name its pass declared" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    const writes = [_][*c]const u8{"backbuffer"};
    var io = std.mem.zeroes(c.ke_render_pass_io);
    io.name = "render.clear";
    io.writes = &writes;
    io.writes_count = 1;

    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    const rp = pass.*.begin_render.?(pass);
    rp.*.end.?(rp);
    svc.*.end_pass.?(svc, pass);
    try testing.expectEqual(true, svc.*.end_frame.?(svc, null));

    try testing.expectEqualStrings("render.clear", std.mem.span(dev.render_pass_label));
}

/// A service over the stubs with a source and a destination color resource and a depth resource
/// declared, and a frame begun.
const PassHarness = struct {
    sd: ShaderDir,
    dev: Stubs.Device,
    ecs: Stubs.Ecs,
    binder: Stubs.Binder,
    target: Stubs.Target,
    h: c.ke_render_service_handle,

    fn init(self: *PassHarness) !void {
        try self.sd.init();
        self.dev.init();
        self.ecs.init();
        self.binder.init();
        self.target.init();
        self.h = ke_render_service_create(self.dev.api(), self.target.api(), self.ecs.api(), self.sd.path(), self.binder.api(), null);
        const svc = self.h.ref orelse return error.TestUnexpectedResult;
        for ([_][*:0]const u8{ "src", "dst" }) |name| {
            var desc = std.mem.zeroes(c.ke_render_resource_params);
            desc.name = name;
            desc.format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
            desc.size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
            desc.scale_x = 1.0;
            desc.scale_y = 1.0;
            try testing.expect(svc.*.declare.?(svc, &desc, null) != c.KE_COMPONENT_INVALID);
        }
        var depth = std.mem.zeroes(c.ke_render_resource_params);
        depth.name = "depth";
        depth.format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT;
        depth.size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
        depth.scale_x = 1.0;
        depth.scale_y = 1.0;
        try testing.expect(svc.*.declare.?(svc, &depth, null) != c.KE_COMPONENT_INVALID);
        try testing.expect(svc.*.begin_frame.?(svc, null));
    }

    fn run(self: *PassHarness, io: *const c.ke_render_pass_io) !void {
        const svc = self.h.ref.?;
        self.dev.render_passes = 0;
        const pass = svc.*.begin_pass.?(svc, io) orelse return error.TestUnexpectedResult;
        const rp = pass.*.begin_render.?(pass);
        rp.*.end.?(rp);
        svc.*.end_pass.?(svc, pass);
    }

    fn deinit(self: *PassHarness) void {
        const svc = self.h.ref.?;
        _ = svc.*.end_frame.?(svc, null);
        self.h.destroy.?(svc);
        self.sd.deinit();
    }
};

test "a pass whose write starts as a resource it reads draws that resource first and then loads the write" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();

    const writes = [_][*c]const u8{"dst"};
    const reads = [_][*c]const u8{"src"};
    var io = std.mem.zeroes(c.ke_render_pass_io);
    io.name = "render.over";
    io.writes = &writes;
    io.writes_count = 1;
    io.reads = &reads;
    io.reads_count = 1;
    io.load_from = "src";
    try ph.run(&io);

    try testing.expectEqual(@as(u32, 2), ph.dev.render_passes);
    try testing.expectEqualStrings("render.over", std.mem.span(ph.dev.render_pass_label));
    try testing.expectEqual(@as(c.ke_gpu_load_op, c.KE_GPU_LOAD_OP_LOAD), ph.dev.color_load);
}

test "a pass that names nothing to start from clears its write in a single render pass" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();

    const writes = [_][*c]const u8{"dst"};
    var io = std.mem.zeroes(c.ke_render_pass_io);
    io.writes = &writes;
    io.writes_count = 1;
    try ph.run(&io);

    try testing.expectEqual(@as(u32, 1), ph.dev.render_passes);
    try testing.expectEqual(@as(c.ke_gpu_load_op, c.KE_GPU_LOAD_OP_CLEAR), ph.dev.color_load);
    try testing.expectEqual(@as(?c.ke_gpu_load_op, null), ph.dev.depth_load);
}

test "a depth resource a pass tests against is attached loaded" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();

    const writes = [_][*c]const u8{"dst"};
    const reads = [_][*c]const u8{"depth"};
    var io = std.mem.zeroes(c.ke_render_pass_io);
    io.writes = &writes;
    io.writes_count = 1;
    io.reads = &reads;
    io.reads_count = 1;
    io.depth_test = "depth";
    try ph.run(&io);

    try testing.expectEqual(@as(?c.ke_gpu_load_op, c.KE_GPU_LOAD_OP_LOAD), ph.dev.depth_load);
}

test "declaring a name again with the same description answers the same resource, and another description is refused" {
    var ph: PassHarness = undefined;
    try ph.init();
    defer ph.deinit();
    const svc = ph.h.ref.?;

    var desc = std.mem.zeroes(c.ke_render_resource_params);
    desc.name = "src";
    desc.format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    desc.size_mode = c.KE_RENDER_SIZE_RELATIVE_TO_BACKBUFFER;
    desc.scale_x = 1.0;
    desc.scale_y = 1.0;
    try testing.expectEqual(svc.*.cid.?(svc, "src"), svc.*.declare.?(svc, &desc, null));
    desc.format = c.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    try testing.expectEqual(@as(c.ke_component_id, c.KE_COMPONENT_INVALID), svc.*.declare.?(svc, &desc, null));
}

test "a compute pass replays at the end of the frame under its name and with the debug groups recorded into it" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    const svc = h.ref orelse return error.TestUnexpectedResult;
    defer h.destroy.?(svc);

    var io = std.mem.zeroes(c.ke_render_pass_io);
    io.name = "render.cull";

    try testing.expectEqual(true, svc.*.begin_frame.?(svc, null));
    const pass = svc.*.begin_pass.?(svc, &io) orelse return error.TestUnexpectedResult;
    const cp = pass.*.begin_compute.?(pass);
    var transient = [_:0]u8{ 'b', 'i', 'n' };
    cp.*.push_debug_group.?(cp, &transient);
    transient[0] = 'x';
    cp.*.pop_debug_group.?(cp);
    cp.*.end.?(cp);
    svc.*.end_pass.?(svc, pass);
    try testing.expect(dev.compute_pass_label == null);
    try testing.expectEqual(true, svc.*.end_frame.?(svc, null));

    try testing.expectEqualStrings("render.cull", std.mem.span(dev.compute_pass_label));
    try testing.expectEqualStrings("bin", std.mem.span(dev.debug_group_label));
    try testing.expectEqual(@as(i32, 0), dev.debug_groups_open);
}

test "a render service created without a shader directory is refused and leaves nothing behind" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), null, binder.api(), null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}


const stress_keys = 64;
const stress_threads = 8;
const stress_rounds = 4;

const Stress = struct {
    svc: *c.ke_render_service,
    params: *[stress_keys]c.ke_gpu_render_pipeline_params,

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
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    try testing.expect(h.ref != null);

    var params: [stress_keys]c.ke_gpu_render_pipeline_params = undefined;
    for (&params, 0..) |*p, i| {
        p.* = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
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
        try testing.expect(first != c.KE_GPU_INVALID_HANDLE);
        try testing.expectEqual(first, pipeline_cache.getOrCreatePipeline(h.ref, p));
    }

    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a pipeline is answered with its fallback first and with the compiled one afterwards" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    try testing.expect(h.ref != null);

    var p = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    p.vertex_module = 5;
    p.fragment_module = 6;
    p.color_target_count = 1;

    const fallback = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    const compiled = pipeline_cache.getOrCreatePipeline(h.ref, &p);
    try testing.expect(fallback != c.KE_GPU_INVALID_HANDLE);
    try testing.expect(compiled != fallback);
    try testing.expectEqual(compiled, pipeline_cache.getOrCreatePipeline(h.ref, &p));

    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a pipeline is keyed by its vertex layout's content, not by where the layout lives" {
    var sd: ShaderDir = undefined;
    try sd.init();
    defer sd.deinit();
    var dev: Stubs.Device = undefined;
    dev.init();
    var ecs: Stubs.Ecs = undefined;
    ecs.init();
    var binder: Stubs.Binder = undefined;
    binder.init();
    var target: Stubs.Target = undefined;
    target.init();
    const h = ke_render_service_create(dev.api(), target.api(), ecs.api(), sd.path(), binder.api(), null);
    try testing.expect(h.ref != null);

    const attrs = [_]c.ke_gpu_vertex_attribute{.{ .shader_location = 0, .format = 0, .offset = 0 }};
    var first_layout = [_]c.ke_gpu_vertex_buffer_layout{.{ .stride = 12, .step_mode = 0, .attribute_count = 1, .attributes = &attrs }};
    var copy_layout = first_layout;

    var p = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
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
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
