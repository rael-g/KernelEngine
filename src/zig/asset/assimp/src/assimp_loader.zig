//! The Assimp implementation of the `ke_asset_loader` contract: it imports a model file into a
//! `ke_model_data` of records that own their memory, synchronously or on the scheduler.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const c = @import("c.zig").c;
const log = @import("log.zig");
const converter = @import("converter.zig");
const textures = @import("texture_decoder.zig");

/// Error helpers from kerror, bound to the C declarations in `c`.
const E = @import("kerror").Errors(c);

/// Vertex count given to Assimp's large-mesh split through the import properties.
const vertex_limit: c_int = 65534;

/// The post-processing every import asks for: triangulated, smooth-shaded geometry with tangent
/// space, merged vertices and flipped texture coordinates, sorted by primitive type and split
/// at `vertex_limit`.
const import_flags: c_uint = c.aiProcess_Triangulate |
    c.aiProcess_GenSmoothNormals |
    c.aiProcess_CalcTangentSpace |
    c.aiProcess_JoinIdenticalVertices |
    c.aiProcess_FlipUVs |
    c.aiProcess_SortByPType |
    c.aiProcess_SplitLargeMeshes;

/// Capacity of the path buffers in each `TextureRef`; a longer name is cut to fit.
const texture_path_max = 1024;

const debug_heap = @import("builtin").mode == .Debug;
const TrackingHeap = std.heap.DebugAllocator(.{ .thread_safe = true });

/// The loader that `ke_asset_loader_assimp_create` allocates and `vtDestroy` frees. The field
/// `handle` of `api` points back at the State, which is how each slot reaches its loader. `gpa` is
/// the allocator every record comes from: the leak-tracking `heap` in a Debug build, and a
/// thread-safe standard allocator otherwise.
const State = struct {
    api: c.ke_asset_loader,
    logger: ?*c.ke_logger,
    heap: if (debug_heap) TrackingHeap else void,
    gpa: std.mem.Allocator,
};

/// Allocator of the `State` alone, kept apart from `gpa` so the leak check does not count the
/// loader's own storage.
const state_heap = std.heap.smp_allocator;

fn stateOf(self: *c.ke_asset_loader) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// One entry of a `TextureTable`. An embedded entry holds in `embedded` the scene texture its index
/// named, which stays null when the index did not resolve; that entry is then decoded from its
/// `resolved_path`, which is empty for an embedded entry. A file entry has its path in
/// `resolved_path` and leaves `embedded` null.
const TextureRef = struct {
    key: [texture_path_max]u8,
    embedded: ?*const c.aiTexture,
    resolved_path: [texture_path_max]u8,
    is_embedded: bool,
};

/// The textures one `loadModel` call needs: one entry per distinct name, shared by every material
/// of the model. It lives only for that call and is released when the call returns; the decoded
/// records it fed are what outlives the call.
const TextureTable = struct {
    items: std.ArrayList(TextureRef),
    gpa: std.mem.Allocator,

    /// Compares against the stored keys, which were cut to fit their buffer, so two names
    /// that agree up to that cut are treated as one entry.
    fn indexOfKey(self: *const TextureTable, key: []const u8) ?u32 {
        for (self.items.items, 0..) |*e, i| {
            if (std.mem.eql(u8, std.mem.sliceTo(&e.key, 0), key)) return @intCast(i);
        }
        return null;
    }
};

/// Called by `loadModel` for each texture kind of each material: base colour before diffuse, and
/// normals before height. It returns the position of the name's entry, adding one the first time
/// the name is seen, or a negative index when the material names no texture of that kind, the name
/// is empty, or the table cannot grow. An embedded name whose index does not parse still gets an
/// entry, with neither an embedded texture nor a path, so its decode falls back.
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
        entry.is_embedded = true;
        const idx = std.fmt.parseInt(u32, key[1..], 10) catch {
            table.items.append(table.gpa, entry) catch return -1;
            return @intCast(table.items.items.len - 1);
        };
        if (idx < scene.mNumTextures) entry.embedded = scene.mTextures[idx];
    } else {
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

/// Performs one whole import and returns the new model, or null on any failure. The scene is
/// imported with `import_flags` and released before the call returns, so the records never refer
/// to it. Materials are converted first, and `registerTexture` collects the textures they name
/// into one `TextureTable` entry per distinct name, so a texture shared by several materials is
/// decoded once; the table is decoded, the indices are written into the materials, and the meshes
/// are converted last, each pointing at its material by index. A texture that cannot be decoded
/// does not fail the load; an import with no usable scene or a failed allocation of the model's
/// arrays does. The failure is
/// written to the out-parameter when the caller gave one; the asynchronous body gives none and
/// relies on the null alone. It runs on the caller's thread for the synchronous slot and on a
/// worker for the asynchronous one. It reads only the logger and the allocator from the State and
/// writes nothing into it.
fn loadModel(s: *State, path: [*c]const u8, out_error: [*c][*c]c.ke_error) ?*c.ke_model_data {
    if (path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }

    const props = c.aiCreatePropertyStore();
    defer c.aiReleasePropertyStore(props);
    c.aiSetImportPropertyInteger(props, c.AI_CONFIG_PP_SLM_VERTEX_LIMIT, vertex_limit);

    const scene_c = c.aiImportFileExWithProperties(path, import_flags, null, props);
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

        albedo_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_BASE_COLOR);
        if (albedo_idx[mi] < 0)
            albedo_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_DIFFUSE);

        normal_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_NORMALS);
        if (normal_idx[mi] < 0)
            normal_idx[mi] = registerTexture(&table, &scene, dir, am, c.aiTextureType_HEIGHT);
    }

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

    for (0..mat_count) |mi| {
        mats[mi].albedo_texture_index = albedo_idx[mi];
        mats[mi].normal_map_texture_index = normal_idx[mi];
    }

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

/// The `load_model` slot, run on the caller's thread. A missing loader or handle is reported here;
/// everything else is reported by `loadModel`.
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

/// The `free_model` slot. It releases the records `loadModel` allocated for a model, through the
/// allocator of the loader it is given, which is the allocator those records were made with. A null
/// loader, handle or model is ignored.
fn vtFreeModel(self_in: ?*c.ke_asset_loader, data_in: ?*c.ke_model_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const data = data_in orelse return;
    const gpa = stateOf(self).gpa;

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

/// Handed to the completion callback when the context for an async load cannot be allocated.
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
/// Handed to an async callback when `loadModel` returned no model. Its message is fixed, so the
/// cause is only what `loadModel` logged, and some failures log nothing.
const load_failed_error = c.ke_error{
    .type = &load_failed_type,
    .message = "model load failed",
    .file = null,
    .line = 0,
    .cause = null,
};

/// The heap context that carries an async load from `vtLoadModelAsync` to `asyncBody`. It owns
/// the path copy and itself; `asyncBody` frees both after the callback returns. `state` is
/// borrowed from the loader, not owned.
const AsyncCtx = struct {
    state: *State,
    path: [:0]u8,
    on_complete: c.ke_load_model_complete_func,
    user_data: ?*anyopaque,
};

/// The task body that the dispatch runs on the thread it chooses. It runs `loadModel`, calls the
/// completion callback once with the model or the load failure, and frees the context. A failure is
/// reported only through the callback: the task's failure out-parameter is left unset.
fn asyncBody(data: ?*anyopaque, out_failure: [*c][*c]const c.ke_error_type) callconv(.c) void {
    _ = out_failure;
    const ctx: *AsyncCtx = @ptrCast(@alignCast(data orelse return));
    const gpa = ctx.state.gpa;
    const model = loadModel(ctx.state, ctx.path.ptr, null);
    if (ctx.on_complete) |done| {
        done(if (model != null) null else &load_failed_error, model, ctx.user_data);
    }
    gpa.free(ctx.path);
    gpa.destroy(ctx);
}

/// The `load_model_async` slot. It returns whatever dispatch returns, and the body may already have
/// run by then if dispatch runs it inline. When the context or its path copy cannot be allocated,
/// the callback is called at once on the calling thread and the result is null.
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

/// The `destroy` slot. It frees the State, and logs a warning, not an error, when the leak check
/// finds live memory. Models that `free_model` has not released are what that check reports.
fn vtDestroy(self_in: ?*c.ke_asset_loader) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (debug_heap) {
        if (s.heap.deinit() == .leak) log.warn(s.logger, "Asset loader destroyed with model memory still live");
    }
    state_heap.destroy(s);
}

/// Factory for the Assimp loader. It returns a handle whose ref is the vtable, or one whose ref is
/// null when the params argument is null or the State cannot be allocated, with the out-parameter
/// filled for those two failures. The logger is kept as the pointer given, and each call builds its
/// own State, so each loader has its own leak tracking in a Debug build.
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
    s.gpa = if (debug_heap) s.heap.allocator() else std.heap.smp_allocator;

    s.api.handle = s;
    s.api.load_model = vtLoadModel;
    s.api.free_model = vtFreeModel;
    s.api.load_model_async = vtLoadModelAsync;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

const testing = std.testing;

fn makeLoader() c.ke_asset_loader_handle {
    var params = std.mem.zeroes(c.ke_asset_loader_assimp_params);
    params.logger = null;
    return ke_asset_loader_assimp_create(&params, null);
}

var box_gltf_buffer: [std.fs.max_path_bytes]u8 = undefined;

const climb_prefixes = [_][]const u8{
    "",
    "../",
    "../../",
    "../../../",
    "../../../../",
    "../../../../../",
    "../../../../../../",
    "../../../../../../../",
};

fn boxGltfPath() ?[:0]const u8 {
    const cwd = std.Io.Dir.cwd();
    for (climb_prefixes) |prefix| {
        const candidate = std.fmt.bufPrintZ(&box_gltf_buffer, "{s}examples/assets/Box.gltf", .{prefix}) catch return null;
        cwd.access(testing.io, candidate, .{ .read = true }) catch continue;
        return candidate;
    }
    return null;
}

fn immediateDispatch(self: [*c]c.ke_scheduler, func: c.ke_task_func, data: ?*anyopaque) callconv(.c) ?*c.ke_task {
    _ = self;
    var failure: [*c]const c.ke_error_type = null;
    if (func) |f| f(data, &failure);
    return @ptrFromInt(1);
}

const AsyncResult = struct {
    done: bool = false,
    failed: bool = false,
    loader: ?*c.ke_asset_loader = null,
};

fn asyncComplete(err: [*c]const c.ke_error, data: ?*c.ke_model_data, user: ?*anyopaque) callconv(.c) void {
    const result: *AsyncResult = @ptrCast(@alignCast(user orelse return));
    result.failed = err != null;
    if (data) |model| {
        const l = result.loader.?;
        l.free_model.?(l, model);
    }
    result.done = true;
}

test "creating a loader without params fails" {
    const h = ke_asset_loader_assimp_create(null, null);
    try testing.expect(h.ref == null);
}

test "creating a loader with params yields a usable vtable" {
    const h = makeLoader();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "loading a null path yields no model" {
    const h = makeLoader();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.load_model.?(h.ref, null, null) == null);
}

test "loading a file that does not exist yields no model" {
    const h = makeLoader();
    defer h.destroy.?(h.ref);

    try testing.expect(h.ref.*.load_model.?(h.ref, "non_existent_file.obj", null) == null);
}

test "freeing a null model is ignored" {
    const h = makeLoader();
    defer h.destroy.?(h.ref);

    h.ref.*.free_model.?(h.ref, null);
}

test "loading the box fixture yields at least one mesh" {
    const path = boxGltfPath() orelse return error.SkipZigTest;

    const h = makeLoader();
    defer h.destroy.?(h.ref);

    const model = h.ref.*.load_model.?(h.ref, path.ptr, null);
    try testing.expect(model != null);
    defer h.ref.*.free_model.?(h.ref, model);

    try testing.expect(model.*.mesh_count > 0);
}

test "the box fixture carries a material alongside its meshes" {
    const path = boxGltfPath() orelse return error.SkipZigTest;

    const h = makeLoader();
    defer h.destroy.?(h.ref);

    const model = h.ref.*.load_model.?(h.ref, path.ptr, null);
    try testing.expect(model != null);
    defer h.ref.*.free_model.?(h.ref, model);

    try testing.expect(model.*.mesh_count > 0);
    try testing.expect(model.*.material_count > 0);
}

test "an async load runs to completion on the scheduler it was given" {
    const path = boxGltfPath() orelse return error.SkipZigTest;

    const h = makeLoader();
    defer h.destroy.?(h.ref);

    var scheduler = std.mem.zeroes(c.ke_scheduler);
    scheduler.dispatch = &immediateDispatch;

    var result = AsyncResult{ .loader = h.ref };
    const task = h.ref.*.load_model_async.?(h.ref, &scheduler, path.ptr, &asyncComplete, &result);

    try testing.expect(task != null);
    try testing.expect(result.done);
    try testing.expect(!result.failed);
}

test "an async load rejects a missing loader scheduler or path" {
    const h = makeLoader();
    defer h.destroy.?(h.ref);

    var scheduler = std.mem.zeroes(c.ke_scheduler);
    scheduler.dispatch = &immediateDispatch;

    try testing.expect(h.ref.*.load_model_async.?(null, &scheduler, "test.obj", &asyncComplete, null) == null);
    try testing.expect(h.ref.*.load_model_async.?(h.ref, null, "test.obj", &asyncComplete, null) == null);
    try testing.expect(h.ref.*.load_model_async.?(h.ref, &scheduler, null, &asyncComplete, null) == null);
}

test "an async load rejects a missing completion callback" {
    const h = makeLoader();
    defer h.destroy.?(h.ref);

    var scheduler = std.mem.zeroes(c.ke_scheduler);
    scheduler.dispatch = &immediateDispatch;

    try testing.expect(h.ref.*.load_model_async.?(h.ref, &scheduler, "test.obj", null, null) == null);
}

test "a malformed model file yields a model carrying no meshes" {
    const cwd = std.Io.Dir.cwd();
    try cwd.writeFile(testing.io, .{ .sub_path = "malformed.obj", .data = "THIS IS NOT VALID OBJ CONTENT\n" });
    defer cwd.deleteFile(testing.io, "malformed.obj") catch {};

    const h = makeLoader();
    defer h.destroy.?(h.ref);

    const model = h.ref.*.load_model.?(h.ref, "malformed.obj", null);
    try testing.expect(model != null);
    defer h.ref.*.free_model.?(h.ref, model);

    try testing.expectEqual(@as(u32, 0), model.*.mesh_count);
}
