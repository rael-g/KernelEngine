// ke_asset_loader backed by Assimp, through Assimp's C API.

const std = @import("std");

// This .so is dlopen'd by a foreign, non-Zig host alongside many sibling
// plugins in one process. std.Thread's default 256 KiB threadlocal signal
// stack exceeds glibc's small static-TLS surplus once enough plugins
// accumulate, aborting with "cannot allocate memory in static TLS block".
pub const std_options: std.Options = .{ .signal_stack_size = null };

// Windows: hand the DLL entry point back to mingw's crtdll. Zig otherwise
// exports a stub _DllMainCRTStartup that skips the CRT bring-up mingw's own
// entry performs — _initialize_onexit_table (so atexit() has a table to write
// into), _initterm over the C and C++ initializer sections, and __main. Assimp
// is C++ with global constructors, so without this every entry point reads
// state that was never constructed; the same libraries linked into an .exe
// work fine, which is what isolated this. Declaring the symbol is enough:
// std.start only exports its own stub when the root module has no such decl.
pub extern fn _DllMainCRTStartup(
    hinst: std.os.windows.HINSTANCE,
    reason: std.os.windows.DWORD,
    reserved: std.os.windows.LPVOID,
) callconv(.winapi) std.os.windows.BOOL;

const c = @import("c.zig").c;
const log = @import("log.zig");
const converter = @import("converter.zig");
const textures = @import("texture_decoder.zig");

const E = @import("kerror").Errors(c);

/// Splits meshes so their indices still fit the engine's 16-bit index buffer.
/// One below 65535 because the splitter treats the limit as exclusive.
const vertex_limit: c_int = 65534;

const import_flags: c_uint = c.aiProcess_Triangulate |
    c.aiProcess_GenSmoothNormals |
    c.aiProcess_CalcTangentSpace |
    c.aiProcess_JoinIdenticalVertices |
    c.aiProcess_FlipUVs |
    c.aiProcess_SortByPType |
    c.aiProcess_SplitLargeMeshes;

/// Longest texture path (embedded reference or resolved file) the loader tracks.
const texture_path_max = 1024;

/// In debug the plugin runs on a tracking allocator, so a model that is never
/// freed is reported by name when the loader is destroyed instead of going
/// unnoticed. Release uses the lock-free general allocator: model loading is
/// dispatched onto the shared worker pool, so it must be safe from any thread.
const debug_heap = @import("builtin").mode == .Debug;
const TrackingHeap = std.heap.DebugAllocator(.{ .thread_safe = true });

const State = struct {
    api: c.ke_asset_loader,
    logger: ?*c.ke_logger, // borrowed
    heap: if (debug_heap) TrackingHeap else void,
    gpa: std.mem.Allocator,
};

/// Allocates the loader's own State. Bootstrap only: the tracking heap cannot
/// hold the struct it lives inside, so this one block comes from the process
/// allocator and is released by the same one in vtDestroy.
const state_heap = std.heap.smp_allocator;

fn stateOf(self: *c.ke_asset_loader) *State {
    return @ptrCast(@alignCast(self.handle));
}

// -- texture table -----------------------------------------------------------

/// One entry per distinct texture reference in the model. Assimp names embedded
/// textures "*N", so the key doubles as the dedup identity and the source.
const TextureRef = struct {
    key: [texture_path_max]u8,
    embedded: ?*const c.aiTexture,
    resolved_path: [texture_path_max]u8,
    is_embedded: bool,
};

const TextureTable = struct {
    items: std.ArrayList(TextureRef),
    gpa: std.mem.Allocator,

    fn indexOfKey(self: *const TextureTable, key: []const u8) ?u32 {
        for (self.items.items, 0..) |*e, i| {
            if (std.mem.eql(u8, std.mem.sliceTo(&e.key, 0), key)) return @intCast(i);
        }
        return null;
    }
};

/// Registers the first texture of `kind` on `mat`, returning its table index, or
/// -1 when the material has none. Repeated references collapse onto one entry.
fn registerTexture(
    table: *TextureTable,
    scene: *const c.aiScene,
    dir: []const u8,
    mat: *const c.aiMaterial,
    kind: c_uint,
) i32 {
    var path: c.aiString = undefined;
    if (c.aiGetMaterialTexture(mat, kind, 0, &path, null, null, null, null, null, null) != c.aiReturn_SUCCESS)
        return -1;

    const key = std.mem.sliceTo(&path.data, 0);
    if (key.len == 0) return -1;
    if (table.indexOfKey(key)) |i| return @intCast(i);

    var entry: TextureRef = .{
        .key = std.mem.zeroes([texture_path_max]u8),
        .embedded = null,
        .resolved_path = std.mem.zeroes([texture_path_max]u8),
        .is_embedded = false,
    };
    const kn = @min(key.len, entry.key.len - 1);
    @memcpy(entry.key[0..kn], key[0..kn]);

    if (key[0] == '*') {
        // "*N" refers to the scene's Nth embedded texture.
        entry.is_embedded = true;
        const idx = std.fmt.parseInt(u32, key[1..], 10) catch {
            // An unparseable reference is kept as an entry so material indices
            // stay stable; it decodes to the white fallback.
            table.items.append(table.gpa, entry) catch return -1;
            return @intCast(table.items.items.len - 1);
        };
        if (idx < scene.mNumTextures) entry.embedded = scene.mTextures[idx];
    } else {
        // External file, relative to the model's own directory.
        var i: usize = 0;
        for (dir) |ch| {
            if (i >= entry.resolved_path.len - 1) break;
            entry.resolved_path[i] = ch;
            i += 1;
        }
        for (key) |ch| {
            if (i >= entry.resolved_path.len - 1) break;
            entry.resolved_path[i] = ch;
            i += 1;
        }
        entry.resolved_path[i] = 0;
    }

    table.items.append(table.gpa, entry) catch return -1;
    return @intCast(table.items.items.len - 1);
}

// -- load --------------------------------------------------------------------

fn loadModel(s: *State, path: [*c]const u8, out_error: [*c][*c]c.ke_error) ?*c.ke_model_data {
    if (path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }

    const props = c.aiCreatePropertyStore();
    defer c.aiReleasePropertyStore(props);
    c.aiSetImportPropertyInteger(props, c.AI_CONFIG_PP_SLM_VERTEX_LIMIT, vertex_limit);

    const scene_c = c.aiImportFileExWithProperties(path, import_flags, null, props);
    // An incomplete scene is treated as a failure: the caller asked for a model,
    // and half of one would surface later as missing geometry.
    if (scene_c == null or scene_c.*.mRootNode == null or
        (scene_c.*.mFlags & c.AI_SCENE_FLAGS_INCOMPLETE) != 0)
    {
        const detail = c.aiGetErrorString();
        log.errCtx(s.logger, "LoadModel", detail);
        E.fail(out_error, .io, if (detail != null) detail else "model import failed", @src());
        if (scene_c != null) c.aiReleaseImport(scene_c);
        return null;
    }
    const scene = scene_c.*;
    defer c.aiReleaseImport(scene_c);

    const gpa = s.gpa;
    const dir = converter.directoryOf(std.mem.span(path));

    var table = TextureTable{ .items = .empty, .gpa = gpa };
    defer table.items.deinit(gpa);

    // -- materials, collecting their texture references -----------------------
    const mat_count = scene.mNumMaterials;
    const mats = gpa.alloc(c.ke_material_data, mat_count) catch {
        E.fail(out_error, .out_of_memory, "material allocation failed", @src());
        return null;
    };
    const albedo_idx = gpa.alloc(i32, mat_count) catch {
        gpa.free(mats);
        E.fail(out_error, .out_of_memory, "material allocation failed", @src());
        return null;
    };
    defer gpa.free(albedo_idx);
    const normal_idx = gpa.alloc(i32, mat_count) catch {
        gpa.free(mats);
        E.fail(out_error, .out_of_memory, "material allocation failed", @src());
        return null;
    };
    defer gpa.free(normal_idx);

    for (0..mat_count) |mi| {
        const am = scene.mMaterials[mi];
        converter.convertMaterial(am, &mats[mi]);

        // glTF's base-colour slot first, then the classic diffuse one.
        albedo_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_BASE_COLOR);
        if (albedo_idx[mi] < 0)
            albedo_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_DIFFUSE);

        // Real normal maps first; HEIGHT is where several exporters put them.
        normal_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_NORMALS);
        if (normal_idx[mi] < 0)
            normal_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_HEIGHT);
    }

    // -- decode the collected textures ---------------------------------------
    const tex_count: u32 = @intCast(table.items.items.len);
    const texs = gpa.alloc(c.ke_texture_data, tex_count) catch {
        gpa.free(mats);
        E.fail(out_error, .out_of_memory, "texture allocation failed", @src());
        return null;
    };
    for (table.items.items, 0..) |*ref, ti| {
        texs[ti] = std.mem.zeroes(c.ke_texture_data);
        if (ref.is_embedded) {
            if (ref.embedded) |et| {
                _ = textures.decodeEmbedded(gpa, et, s.logger, &texs[ti]);
            } else {
                _ = textures.decodeExternal(gpa, @ptrCast(&ref.resolved_path), s.logger, &texs[ti]);
            }
        } else {
            _ = textures.decodeExternal(gpa, @ptrCast(&ref.resolved_path), s.logger, &texs[ti]);
        }
    }

    // Patched only now: the indices are into the table that decoding just filled.
    for (0..mat_count) |mi| {
        mats[mi].albedo_texture_index = albedo_idx[mi];
        mats[mi].normal_map_texture_index = normal_idx[mi];
    }

    // -- meshes ---------------------------------------------------------------
    const mesh_count = scene.mNumMeshes;
    const meshes = gpa.alloc(c.ke_mesh_data, mesh_count) catch {
        gpa.free(mats);
        gpa.free(texs);
        E.fail(out_error, .out_of_memory, "mesh allocation failed", @src());
        return null;
    };
    for (0..mesh_count) |si| {
        const am = scene.mMeshes[si];
        _ = converter.convertMesh(gpa, am, &meshes[si]);
        // Out-of-range material references become -1 rather than indexing past
        // the material array.
        meshes[si].material_index = if (am.*.mMaterialIndex < mat_count)
            @intCast(am.*.mMaterialIndex)
        else
            -1;
    }

    const model = gpa.create(c.ke_model_data) catch {
        gpa.free(mats);
        gpa.free(texs);
        gpa.free(meshes);
        E.fail(out_error, .out_of_memory, "model allocation failed", @src());
        return null;
    };
    model.* = .{
        .meshes = meshes.ptr,
        .mesh_count = mesh_count,
        .materials = mats.ptr,
        .material_count = mat_count,
        .textures = texs.ptr,
        .texture_count = tex_count,
    };

    log.info(s.logger, "Model loaded successfully");
    return model;
}

// -- vtable ------------------------------------------------------------------

fn vtLoadModel(
    self_in: ?*c.ke_asset_loader,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) ?*c.ke_model_data {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    };
    if (self.handle == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }
    return loadModel(stateOf(self), path, out_error);
}

/// Releases a model this loader produced. Every block came from the loader's
/// own allocator, so the model must be handed back to the same loader that
/// returned it — a foreign or hand-built ke_model_data is not a valid argument.
fn vtFreeModel(self_in: ?*c.ke_asset_loader, data_in: ?*c.ke_model_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const data = data_in orelse return;
    const gpa = stateOf(self).gpa;

    // The C records hold [*c] pointers; recast to plain many-item pointers so a
    // slice can be rebuilt from the count that travels with each array.
    if (data.meshes) |raw| {
        const meshes: [*]c.ke_mesh_data = @ptrCast(raw);
        for (0..data.mesh_count) |i| converter.freeMesh(gpa, &meshes[i]);
        gpa.free(meshes[0..data.mesh_count]);
    }
    if (data.materials) |raw| {
        const mats: [*]c.ke_material_data = @ptrCast(raw);
        gpa.free(mats[0..data.material_count]);
    }
    if (data.textures) |raw| {
        const texs: [*]c.ke_texture_data = @ptrCast(raw);
        for (0..data.texture_count) |i| textures.freePixels(gpa, &texs[i]);
        gpa.free(texs[0..data.texture_count]);
    }
    gpa.destroy(data);
}

// -- async -------------------------------------------------------------------

// Program-lifetime errors for the async path: the completion callback may run
// after the failing frame is gone, so the error it receives cannot point into
// a thread-local slot.
const oom_error = c.ke_error{
    .type = E.typeOf(.out_of_memory),
    .message = "out of memory preparing async model load",
    .file = null,
    .line = 0,
    .cause = null,
};
const load_failed_type = c.ke_error_type{
    .name = "ke.asset.assimp.load_failed",
    .parent = E.typeOf(.io),
};
const load_failed_error = c.ke_error{
    .type = &load_failed_type,
    .message = "model load failed",
    .file = null,
    .line = 0,
    .cause = null,
};

const AsyncCtx = struct {
    state: *State,
    path: [:0]u8, // owned copy; the caller's buffer may not outlive the task
    on_complete: c.ke_load_model_complete_func,
    user_data: ?*anyopaque,
};

fn asyncBody(data: ?*anyopaque) callconv(.c) void {
    const ctx: *AsyncCtx = @ptrCast(@alignCast(data orelse return));
    const gpa = ctx.state.gpa;
    const model = loadModel(ctx.state, ctx.path.ptr, null);
    if (ctx.on_complete) |done| {
        done(if (model != null) null else &load_failed_error, model, ctx.user_data);
    }
    gpa.free(ctx.path);
    gpa.destroy(ctx);
}

fn vtLoadModelAsync(
    self_in: ?*c.ke_asset_loader,
    scheduler_in: ?*c.ke_scheduler,
    path: [*c]const u8,
    on_complete: c.ke_load_model_complete_func,
    user_data: ?*anyopaque,
) callconv(.c) ?*c.ke_task {
    const self = self_in orelse return null;
    const scheduler = scheduler_in orelse return null;
    if (self.handle == null or path == null or on_complete == null) return null;

    const s = stateOf(self);
    const gpa = s.gpa;

    const ctx = gpa.create(AsyncCtx) catch {
        on_complete.?(&oom_error, null, user_data);
        return null;
    };
    const path_copy = gpa.dupeZ(u8, std.mem.span(path)) catch {
        gpa.destroy(ctx);
        on_complete.?(&oom_error, null, user_data);
        return null;
    };

    ctx.* = .{
        .state = s,
        .path = path_copy,
        .on_complete = on_complete,
        .user_data = user_data,
    };

    return scheduler.dispatch.?(scheduler, asyncBody, ctx);
}

fn vtDestroy(self_in: ?*c.ke_asset_loader) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (debug_heap) {
        // Reports every model the host loaded and never freed, with the stack
        // that allocated it, instead of letting the leak pass unremarked.
        if (s.heap.deinit() == .leak) log.warn(s.logger, "Asset loader destroyed with model memory still live");
    }
    state_heap.destroy(s);
}

// -- factory -----------------------------------------------------------------

export fn ke_asset_loader_assimp_create(
    params_in: ?*const c.ke_asset_loader_assimp_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_asset_loader_handle {
    const null_handle = std.mem.zeroes(c.ke_asset_loader_handle);

    const params = params_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const s = state_heap.create(State) catch {
        E.fail(out_error, .out_of_memory, "loader allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_asset_loader),
        .logger = params.logger,
        .heap = if (debug_heap) .init else {},
        .gpa = undefined,
    };
    // Bound after the struct is in its final place: the tracking heap's
    // interface holds a pointer back into the field it lives in.
    s.gpa = if (debug_heap) s.heap.allocator() else std.heap.smp_allocator;

    s.api.handle = s;
    s.api.load_model = vtLoadModel;
    s.api.free_model = vtFreeModel;
    s.api.load_model_async = vtLoadModelAsync;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}
