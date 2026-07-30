const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const c = @cImport({
    @cInclude("kernel_engine/ecs/ke_ecs.h");
    @cInclude("kernel_engine/render/gpu/gpu_device.h");
    @cInclude("kernel_engine/render/gpu/gpu_commands.h");
    @cInclude("kernel_engine/render/gpu/gpu_surface_ext.h");
    @cInclude("kernel_engine/render/service/render_service.h");
    @cInclude("kernel_engine/render/service/pass_context.h");
    @cInclude("kernel_engine/resource_cache/resource_cache.h");
});

pub const gpa = @import("heap.zig").gpa;

// Fold the render module factory (ke_render_module_create) into this lib so it
// calls ke_render_service_create in-lib — a separate Zig DLL can't link this one's
// import lib on Windows. Force-referenced so its export fn is emitted.
comptime {
    _ = @import("render_module.zig");
}

// This file holds only the shared state (CoreState + its small accessor
// methods), the factory/destroy pair, and the vtable wiring. Each vtable
// slot's actual logic lives in its own file, grouped by concern rather than
// by "everything the core does":
//   resource_table.zig   — named-resource declare/import/lookup (tag cids)
//   pass_recording.zig    — ke_render_pass_ctx + the compute-pass proxy
//   frame_lifecycle.zig   — begin/end_frame + the deferred-upload recorder
//   asset_upload.zig      — mesh/texture/cubemap/material upload
// The core provides mechanism only. A rendering feature — anything owning a
// pipeline, shaders, or per-frame draw state — belongs to a pass module, not
// to this vtable.
const resource_table = @import("resource_table.zig");
const pass_recording = @import("pass_recording.zig");
const frame_lifecycle = @import("frame_lifecycle.zig");
const asset_upload = @import("asset_upload.zig");
const pipeline_cache = @import("pipeline_cache.zig");
const slot_map = @import("slot_map.zig");
const shader_loader = @import("shader_loader.zig");

pub const MAX_RESOURCES = 64;
pub const MAX_CMD_BUFFERS = 64;
pub const NUM_PRECREATED_ENCODERS = 9; // command encoders pre-created per frame (≥ pass count)
pub const MAX_COLOR_ATTACH = 8;
pub const MAX_UPLOADS = 4096; // deferred buffer uploads per frame
// An authored-material shader name is a file stem (a build artifact), not a
// game-tuning value — this bounds an identifier, not a workload.
pub const MAX_SHADER_NAME = 64;
pub const DEFAULT_MATERIAL_SHADER = "standard";
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
    alpha_mode: c.ke_alpha_mode, // CPU-side only — gates gbuffer vs transparent-forward, no GPU state
    alpha_cutoff: f32, // MASK discard threshold; unused for OPAQUE/BLEND
    // CPU-side only — the authored-material shader name (file stem of a
    // `struct X : IMaterial` .slang). A drawing pass concatenates
    // "<shader>.<pass>" and resolves that PSO via load_shader; this field
    // carries no GPU state itself, same as alpha_mode above. Stored inline
    // (NUL-terminated) so the material owns the string; MAX_SHADER_NAME bounds
    // a build-artifact identifier, not a game-tuning value.
    shader: [MAX_SHADER_NAME]u8,
    // The textures this material's bind group samples, held with one reference
    // each (retained at create, released when the material is destroyed). Keeps
    // the bind group's views alive independently of the caller's own references
    // to those textures — releasing a shared texture elsewhere can't dangle this
    // material. Resolved values (fallbacks included), not the caller's raw args.
    albedo: c.ke_texture_handle,
    normal: c.ke_texture_handle,
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
    // Non-texture producer outputs published under the same name→cid table, so a
    // consumer pass never holds a pointer to the producing pass's private struct
    // (e.g. shadow publishes its LVP uniform buffer, cluster its light-list bind
    // group) — the same "look it up by name" contract textures already use.
    buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    buffer_size: u64 = 0,
    bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE,
    // The layout the bind group was built from — a consumer building its own
    // pipeline needs this at setup time (the bind group instance alone isn't
    // enough to declare a matching bind_group_layouts[] slot).
    bind_group_layout: c.ke_gpu_bind_group_layout = c.KE_GPU_INVALID_HANDLE,
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

    clear_color: [4]f32,

    // Resource storage: generational slot maps (grow on demand, recycle freed
    // slots, detect stale handles). Ownership + refcount + path-dedup live in the
    // matching ke_resource_cache; the slot map is just the backing store the
    // cache's destroy callback empties. Cubemaps share the texture store.
    mesh_store: slot_map.SlotMap(Mesh),
    texture_store: slot_map.SlotMap(Texture),
    material_store: slot_map.SlotMap(Material),
    // One cache per owned resource kind (see resource_cache.h: a cache never
    // inspects its handles, so each kind gets its own instance + destroy_fn).
    mesh_cache: *c.ke_resource_cache,
    texture_cache: *c.ke_resource_cache,
    material_cache: *c.ke_resource_cache,
    mesh_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    texture_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    material_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,

    // Shader modules: a 4th owned resource kind, deduped by resolved file path
    // (see shader_loader.zig). Never released by a pass — lives for the core's
    // lifetime, freed at teardown like the built-in mesh/texture/material.
    shader_store: slot_map.SlotMap(c.ke_gpu_shader_module),
    shader_cache: *c.ke_resource_cache,
    shader_cache_destroy: *const fn (*c.ke_resource_cache) callconv(.c) void,
    // Absolute path to the directory build-time-compiled shaders were
    // installed into (owned, allocated at create). load_shader resolves
    // "<shader_dir>/<name>.<stage-suffix>.<ext>" against this.
    shader_dir: []const u8,

    sampler: c.ke_gpu_sampler, // shared linear-repeat sampler
    material_bgl: c.ke_gpu_bind_group_layout, // set 1 layout
    default_normal: c.ke_texture_handle, // built-in flat (0,0,1) normal map
    default_cubemap: c.ke_texture_handle, // built-in 1×1 black env cubemap
    white_texture_h: c.ke_texture_handle, // built-in 1×1 white — solid-color UI quads sample this
    white_material: c.ke_material_handle, // built-in white material — stale/unknown material handles resolve here

    ndc: c.ke_ndc_convention, // backend clip-space convention (queried at setup)

    // PSO dedup + lifecycle (§6 Mechanism 1) — the core is the sole owner of
    // every ke_gpu_pipeline; passes request, never create/destroy directly.
    pipeline_cache: pipeline_cache.PipelineCache,

    // Resolve a handle to its payload, or null if the handle is stale/unknown.
    // Callers decide the fallback (a neutral resource, or an error) — the store
    // never silently substitutes one resource for another.
    pub fn meshAt(self: *CoreState, h: c.ke_mesh_handle) ?*Mesh {
        return self.mesh_store.get(h.bits);
    }

    pub fn textureAt(self: *CoreState, h: c.ke_texture_handle) ?*Texture {
        return self.texture_store.get(h.bits);
    }

    // Falls back to the built-in white material for a stale/unknown handle, so a
    // draw with a released material renders visibly-neutral instead of reading
    // freed memory. A pass that needs to distinguish the two checks material_store
    // directly.
    pub fn materialAt(self: *CoreState, h: c.ke_material_handle) *Material {
        return self.material_store.get(h.bits) orelse
            self.material_store.get(self.white_material.bits).?;
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

pub inline fn coreOf(self: [*c]c.ke_render_service) *CoreState {
    return @alignCast(@ptrCast(self.*.handle));
}
pub inline fn passOf(self: [*c]c.ke_render_pass_ctx) *PassState {
    return @alignCast(@ptrCast(self.*.handle));
}

pub fn isDepthFormat(fmt: c.ke_gpu_texture_format) bool {
    return fmt >= c.KE_GPU_TEXTURE_FORMAT_D16_UNORM and fmt <= c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

// ── Factory + destroy ───────────────────────────────────────────────────────

fn destroyCore(self: [*c]c.ke_render_service) callconv(.c) void {
    const st = coreOf(self);
    // Must run before pipeline_cache.destroyAll: an in-flight async compile's
    // on_ready callback writes into a pipeline_cache Entry, so destroying the
    // cache (or the CoreState it lives in) before every dispatched compile has
    // fired would race a callback against freed memory.
    if (st.device.flush_pipeline_compiles) |flush| flush(st.device);
    var i: u32 = 0;
    while (i < st.resource_count) : (i += 1) {
        const r = &st.resources[i];
        if (r.is_transient) {
            if (r.view != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture_view.?(st.device, r.view);
            if (r.texture != c.KE_GPU_INVALID_HANDLE) st.device.destroy_texture.?(st.device, r.texture);
        }
    }
    // Destroying a cache fires its destroy_fn for every still-live resource,
    // which removes it from its slot map and destroys the GPU objects. Materials
    // before textures: a material's destroy releases the textures its bind group
    // samples, so those textures must still be resident when it runs.
    st.material_cache_destroy(st.material_cache);
    st.texture_cache_destroy(st.texture_cache);
    st.mesh_cache_destroy(st.mesh_cache);
    st.shader_cache_destroy(st.shader_cache);
    st.material_store.deinit();
    st.texture_store.deinit();
    st.mesh_store.deinit();
    st.shader_store.deinit();
    if (st.sampler != c.KE_GPU_INVALID_HANDLE) st.device.destroy_sampler.?(st.device, st.sampler);
    st.pipeline_cache.destroyAll(st.device);
    gpa.free(st.upload_arena);
    gpa.free(@constCast(st.shader_dir));
    gpa.destroy(st);
    gpa.destroy(@as(*c.ke_render_service, @ptrCast(self)));
}

export fn ke_render_service_create(device: ?*c.ke_gpu_device, ecs: ?*c.ke_ecs, shader_dir: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_service_handle {
    const dev = device orelse return .{ .ref = null, .destroy = null };
    const e = ecs orelse return .{ .ref = null, .destroy = null };
    const shader_dir_span = if (shader_dir != null) std.mem.span(shader_dir) else {
        c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ke_render_service_create: shader_dir is required", @src().file, @intCast(@src().line), null);
        return .{ .ref = null, .destroy = null };
    };

    const st = gpa.create(CoreState) catch return .{ .ref = null, .destroy = null };
    const upload_arena = gpa.alloc(u8, UPLOAD_ARENA_SIZE) catch {
        gpa.destroy(st);
        return .{ .ref = null, .destroy = null };
    };
    const shader_dir_owned = gpa.dupe(u8, shader_dir_span) catch {
        gpa.free(upload_arena);
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
        .sampler = c.KE_GPU_INVALID_HANDLE,
        .material_bgl = c.KE_GPU_INVALID_HANDLE,
        .default_normal = .{ .bits = c.KE_HANDLE_NONE },
        .default_cubemap = .{ .bits = c.KE_HANDLE_NONE },
        .white_texture_h = .{ .bits = c.KE_HANDLE_NONE },
        .white_material = .{ .bits = c.KE_HANDLE_NONE },
        .ndc = dev.get_ndc_convention.?(dev),
        .pipeline_cache = pipeline_cache.PipelineCache.init(),
    };

    // The four owning caches. Each destroy_fn empties the matching slot map and
    // destroys the GPU objects; destroy_ctx is the core so the callback can reach
    // the device + stores. A failure here leaves earlier caches leaked on the
    // error path, but a cache alloc failing at startup is fatal anyway.
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
        .import_bind_group = resource_table.importBindGroup,
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
        .material_alpha_mode = asset_upload.materialAlphaMode,
        .material_alpha_cutoff = asset_upload.materialAlphaCutoff,
        .upload_cubemap = asset_upload.uploadCubemap,
        .texture_view = asset_upload.textureView,
        .sampler = asset_upload.samplerOf,
        .resource_view = resource_table.resourceView,
        .resource_texture = resource_table.resourceTexture,
        .resource_buffer = resource_table.resourceBuffer,
        .resource_buffer_size = resource_table.resourceBufferSize,
        .resource_bind_group = resource_table.resourceBindGroup,
        .resource_bind_group_layout = resource_table.resourceBindGroupLayout,
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
    // Built-in singletons: engine-reserved keys (never a real asset path, so no
    // game content can collide with them) — every upload is cache-registered,
    // no exceptions. The core keeps the one reference each starts with, so they
    // live until teardown. A stale/none albedo, normal, or material handle
    // resolves to these.
    const white_px = [_]u8{ 255, 255, 255, 255 };
    st.white_texture_h = asset_upload.uploadTexture(core, "__ke_white_texture", 1, 1, &white_px, null);
    const flat_normal_px = [_]u8{ 128, 128, 255, 255 }; // (0,0,1) in tangent space
    st.default_normal = asset_upload.uploadTexture(core, "__ke_default_normal", 1, 1, &flat_normal_px, null);
    const black_cube_px = [_]u8{0} ** (4 * 6); // 1×1 black on all 6 faces
    st.default_cubemap = asset_upload.uploadCubemap(core, "__ke_default_cubemap", 1, &black_cube_px, null);
    const white_color = [_]f32{ 1.0, 1.0, 1.0, 1.0 };
    st.white_material = asset_upload.createMaterial(core, "__ke_white_material", &white_color, 0.0, 0.5, .{ .bits = c.KE_HANDLE_NONE }, .{ .bits = c.KE_HANDLE_NONE }, c.KE_ALPHA_MODE_OPAQUE, 0.5, 1.5, 0.05, null, null);

    return .{ .ref = core, .destroy = destroyCore };
}
