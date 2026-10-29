//! The Assimp implementation of the `ke_asset_loader` contract: it imports a model file into a
//! `ke_model_data` of records that own their memory, synchronously or on the task pool.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_asset_assimp").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const c = @import("c");
const abi_asset = @import("abi_asset");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");
const abi_task_pool = @import("abi_task_pool");
const log = std.log.scoped(.asset_assimp);
const converter = @import("converter.zig");
const textures = @import("texture_decoder.zig");
const io_files = @import("io_files.zig");

const R = @import("result").Result(.{});

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
/// thread-safe standard allocator otherwise. `io` is borrowed from the factory's caller, and every
/// file an import opens is read through it.
const State = struct {
    api: abi_asset.ke_asset_loader,
    io: *abi_io.ke_io,
    heap: if (debug_heap) TrackingHeap else void,
    gpa: std.mem.Allocator,
};

/// Allocator of the `State` alone, kept apart from `gpa` so the leak check does not count the
/// loader's own storage.
const state_heap = std.heap.smp_allocator;

fn stateOf(self: *abi_asset.ke_asset_loader) *State {
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
/// does not fail the load; an import with no usable scene, which fails with io and logs Assimp's
/// reason, or a failed allocation of the model's arrays does. It runs on the caller's thread for
/// the synchronous slot and on a worker for the asynchronous one. It reads only the allocator from
/// the State and writes nothing into it.
fn loadModel(s: *State, path: [*c]const u8) R.Error!*abi_asset.ke_model_data {
    if (path == null) {
                return error.InvalidArgument;
    }

    const props = c.aiCreatePropertyStore();
    defer c.aiReleasePropertyStore(props);
    c.aiSetImportPropertyInteger(props, c.AI_CONFIG_PP_SLM_VERTEX_LIMIT, vertex_limit);

    var file_io = io_files.of(s.io);
    const scene_c = c.aiImportFileExWithProperties(path, import_flags, &file_io, props);
    if (scene_c == null or scene_c.*.mRootNode == null or
        (scene_c.*.mFlags & c.AI_SCENE_FLAGS_INCOMPLETE) != 0)
    {
        const detail = c.aiGetErrorString();
        log.warn("{s}: {s}", .{ std.mem.span(path), if (detail != null) std.mem.span(detail) else "(no detail)" });
                if (scene_c != null) c.aiReleaseImport(scene_c);
        return error.Io;
    }
    const scene = scene_c.*;
    defer c.aiReleaseImport(scene_c);

    const gpa = s.gpa;
    const dir = converter.directoryOf(std.mem.span(path));

    var table = TextureTable{ .items = .empty, .gpa = gpa };
    defer table.items.deinit(gpa);

    const mat_count = scene.mNumMaterials;
    const mats = gpa.alloc(abi_asset.ke_material_data, mat_count) catch {
                return error.OutOfMemory;
    };
    const albedo_idx = gpa.alloc(i32, mat_count) catch {
        gpa.free(mats);
                return error.OutOfMemory;
    };
    defer gpa.free(albedo_idx);
    const normal_idx = gpa.alloc(i32, mat_count) catch {
        gpa.free(mats);
                return error.OutOfMemory;
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
    const texs = gpa.alloc(abi_asset.ke_texture_data, tex_count) catch {
        gpa.free(mats);
                return error.OutOfMemory;
    };
    for (table.items.items, 0..) |*ref, ti| {
        texs[ti] = std.mem.zeroes(abi_asset.ke_texture_data);
        if (ref.is_embedded) {
            if (ref.embedded) |et| {
                _ = textures.decodeEmbedded(gpa, et, &texs[ti]);
            } else {
                _ = textures.decodeExternal(gpa, s.io, @ptrCast(&ref.resolved_path), &texs[ti]);
            }
        } else {
            _ = textures.decodeExternal(gpa, s.io, @ptrCast(&ref.resolved_path), &texs[ti]);
        }
    }

    for (0..mat_count) |mi| {
        mats[mi].albedo_texture_index = albedo_idx[mi];
        mats[mi].normal_map_texture_index = normal_idx[mi];
    }

    const mesh_count = scene.mNumMeshes;
    const meshes = gpa.alloc(abi_asset.ke_mesh_data, mesh_count) catch {
        gpa.free(mats);
        gpa.free(texs);
                return error.OutOfMemory;
    };
    for (0..mesh_count) |si| {
        const am = scene.mMeshes[si];
        _ = converter.convertMesh(gpa, am, &meshes[si]);
        meshes[si].material_index = if (am.*.mMaterialIndex < mat_count)
            @intCast(am.*.mMaterialIndex)
        else
            -1;
    }

    const model = gpa.create(abi_asset.ke_model_data) catch {
        gpa.free(mats);
        gpa.free(texs);
        gpa.free(meshes);
                return error.OutOfMemory;
    };
    model.* = .{
        .meshes = meshes.ptr,
        .mesh_count = mesh_count,
        .materials = mats.ptr,
        .material_count = mat_count,
        .textures = texs.ptr,
        .texture_count = tex_count,
    };

    log.info("{s}: loaded", .{std.mem.span(path)});
    return model;
}

/// The `load_model` slot, run on the caller's thread. A missing loader, handle or out-parameter is
/// an invalid argument; everything else is reported by `loadModel`.
fn vtLoadModel(
    self_in: ?*abi_asset.ke_asset_loader,
    path: [*c]const u8,
    out_model: ?*?*abi_asset.ke_model_data,
) callconv(.c) abi_result.ke_result {
    const out = out_model orelse return R.code(error.InvalidArgument);
    out.* = null;
    const self = self_in orelse return R.code(error.InvalidArgument);
    if (self.handle == null) return R.code(error.InvalidArgument);
    out.* = loadModel(stateOf(self), path) catch |err| return R.code(err);
    return R.ok;
}

/// The `free_model` slot. It releases the records `loadModel` allocated for a model, through the
/// allocator of the loader it is given, which is the allocator those records were made with. A null
/// loader, handle or model is ignored.
fn vtFreeModel(self_in: ?*abi_asset.ke_asset_loader, data_in: ?*abi_asset.ke_model_data) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const data = data_in orelse return;
    const gpa = stateOf(self).gpa;

    if (data.meshes) |raw| {
        const meshes: [*]abi_asset.ke_mesh_data = @ptrCast(raw);
        for (0..data.mesh_count) |i| converter.freeMesh(gpa, &meshes[i]);
        gpa.free(meshes[0..data.mesh_count]);
    }
    if (data.materials) |raw| {
        const mats: [*]abi_asset.ke_material_data = @ptrCast(raw);
        gpa.free(mats[0..data.material_count]);
    }
    if (data.textures) |raw| {
        const texs: [*]abi_asset.ke_texture_data = @ptrCast(raw);
        for (0..data.texture_count) |i| textures.freePixels(gpa, &texs[i]);
        gpa.free(texs[0..data.texture_count]);
    }
    gpa.destroy(data);
}

/// The heap context that carries an async load from `vtLoadModelAsync` to `asyncBody`. It owns
/// the path copy and itself; `asyncBody` frees both after the callback returns. `state` is
/// borrowed from the loader, not owned.
const AsyncCtx = struct {
    state: *State,
    path: [:0]u8,
    on_complete: abi_asset.ke_load_model_complete_func,
    user_data: ?*anyopaque,
};

/// The task body that the dispatch runs on the thread it chooses. It runs `loadModel`, calls the
/// completion callback once with the model or the load failure, and frees the context. A failure is
/// reported only through the callback, so the task itself returns OK.
fn asyncBody(data: ?*anyopaque) callconv(.c) abi_result.ke_result {
    const ctx: *AsyncCtx = @ptrCast(@alignCast(data orelse return R.ok));
    const gpa = ctx.state.gpa;
    const loaded = loadModel(ctx.state, ctx.path.ptr);
    if (ctx.on_complete) |done| {
        if (loaded) |model| done(R.ok, model, ctx.user_data) else |err| done(R.code(err), null, ctx.user_data);
    }
    gpa.free(ctx.path);
    gpa.destroy(ctx);
    return R.ok;
}

/// The `load_model_async` slot. It returns whatever dispatch returns, and the body may already have
/// run by then if dispatch runs it inline. When the context or its path copy cannot be allocated,
/// the callback is called at once on the calling thread and the result is null.
fn vtLoadModelAsync(
    self_in: ?*abi_asset.ke_asset_loader,
    task_pool_in: ?*abi_task_pool.ke_task_pool,
    path: [*c]const u8,
    on_complete: abi_asset.ke_load_model_complete_func,
    user_data: ?*anyopaque,
) callconv(.c) ?*abi_task_pool.ke_task {
    const self = self_in orelse return null;
    const task_pool = task_pool_in orelse return null;
    if (self.handle == null or path == null or on_complete == null) return null;

    const s = stateOf(self);
    const gpa = s.gpa;

    const ctx = gpa.create(AsyncCtx) catch {
        on_complete.?(R.code(error.OutOfMemory), null, user_data);
        return null;
    };
    const path_copy = gpa.dupeZ(u8, std.mem.span(path)) catch {
        gpa.destroy(ctx);
        on_complete.?(R.code(error.OutOfMemory), null, user_data);
        return null;
    };

    ctx.* = .{
        .state = s,
        .path = path_copy,
        .on_complete = on_complete,
        .user_data = user_data,
    };

    var task: ?*abi_task_pool.ke_task = null;
    R.check(task_pool.dispatch.?(task_pool, asyncBody, ctx, &task)) catch |err| {
        log.warn("loading {s} asynchronously failed: the task pool refused it: {t}", .{ path, err });
        gpa.free(path_copy);
        gpa.destroy(ctx);
        on_complete.?(R.code(err), null, user_data);
        return null;
    };
    return task;
}

/// The `destroy` slot. It frees the State, and logs a warning, not an error, when the leak check
/// finds live memory. Models that `free_model` has not released are what that check reports.
fn vtDestroy(self_in: ?*abi_asset.ke_asset_loader) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    if (debug_heap) {
        if (s.heap.deinit() == .leak) log.warn("destroyed with model memory still live", .{});
    }
    state_heap.destroy(s);
}

/// Factory for the Assimp loader. It writes a handle whose ref is the vtable, or fails with out of
/// memory, the handle zeroed, when the State cannot be allocated. Each call builds its own State, so
/// each loader has its own leak tracking in a Debug build.
export fn ke_asset_loader_assimp_create(io_in: ?*abi_io.ke_io, out_loader: ?*abi_asset.ke_asset_loader_handle) callconv(.c) abi_result.ke_result {
    const out = out_loader orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_asset.ke_asset_loader_handle);
    const io = io_in orelse return R.code(error.InvalidArgument);

    const s = state_heap.create(State) catch {
        log.warn("creating the model loader failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    s.* = .{
        .api = std.mem.zeroes(abi_asset.ke_asset_loader),
        .io = io,
        .heap = if (debug_heap) .init else {},
        .gpa = undefined,
    };
    s.gpa = if (debug_heap) s.heap.allocator() else std.heap.smp_allocator;

    s.api.handle = s;
    s.api.load_model = vtLoadModel;
    s.api.free_model = vtFreeModel;
    s.api.load_model_async = vtLoadModelAsync;

    out.* = .{ .ref = &s.api, .destroy = vtDestroy };
    return R.ok;
}

const testing = std.testing;

const zsub = @import("zsub");

const triangle_obj = "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n";

var served: ?[]const u8 = null;
var request_token: u8 = 0;

fn readServed(args: zsub.For(abi_io.ke_io).Args(.read_file)) abi_result.ke_result {
    args[2].?.* = @ptrCast(&request_token);
    return R.ok;
}

fn waitServed(args: zsub.For(abi_io.ke_io).Args(.wait)) abi_result.ke_result {
    const bytes = served orelse return R.code(error.NotFound);
    if (args[2]) |out| {
        out.* = std.mem.zeroes(abi_io.ke_io_result);
        out.bytes = @constCast(bytes.ptr);
        out.size = bytes.len;
    }
    return R.ok;
}

fn freeServed(_: zsub.For(abi_io.ke_io).Args(.free_bytes)) void {}

/// A substitute io serving `bytes` for every path, or no file at all when `bytes` is null.
const ServedIo = struct {
    sub: zsub.For(abi_io.ke_io),

    fn init(self: *ServedIo, bytes: ?[]const u8) !void {
        served = bytes;
        try self.sub.init();
        _ = self.sub.when(.read_file).does(readServed);
        _ = self.sub.when(.wait).does(waitServed);
        _ = self.sub.when(.free_bytes).does(freeServed);
    }

    fn deinit(self: *ServedIo) void {
        self.sub.deinit();
    }

    fn loader(self: *ServedIo) abi_asset.ke_asset_loader_handle {
        var h = std.mem.zeroes(abi_asset.ke_asset_loader_handle);
        _ = ke_asset_loader_assimp_create(self.sub.api(), &h);
        return h;
    }
};

fn immediateDispatch(self: [*c]abi_task_pool.ke_task_pool, func: abi_task_pool.ke_task_func, data: ?*anyopaque, out_task: [*c]?*abi_task_pool.ke_task) callconv(.c) abi_result.ke_result {
    _ = self;
    if (func) |f| _ = f(data);
    out_task.* = @ptrFromInt(1);
    return R.ok;
}

const AsyncResult = struct {
    done: bool = false,
    failed: bool = false,
    loader: ?*abi_asset.ke_asset_loader = null,
};

fn asyncComplete(code: abi_result.ke_result, data: ?*abi_asset.ke_model_data, user: ?*anyopaque) callconv(.c) void {
    const result: *AsyncResult = @ptrCast(@alignCast(user orelse return));
    result.failed = code != R.ok;
    if (data) |model| {
        const l = result.loader.?;
        l.free_model.?(l, model);
    }
    result.done = true;
}

test "creating a loader yields a usable vtable" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
}

test "creating without an io is refused and leaves the handle zeroed" {
    var h = std.mem.zeroes(abi_asset.ke_asset_loader_handle);
    try testing.expectError(error.InvalidArgument, R.check(ke_asset_loader_assimp_create(null, &h)));
    try testing.expect(h.ref == null and h.destroy == null);
}

test "loading a null path yields no model" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var model: ?*abi_asset.ke_model_data = null;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_model.?(h.ref, null, &model)));
}

test "loading a file the io does not find yields no model" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var model: ?*abi_asset.ke_model_data = null;
    try testing.expectError(error.Io, R.check(h.ref.?.load_model.?(h.ref, "missing.obj", &model)));
    try testing.expect(model == null);
}

test "freeing a null model is ignored" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    h.ref.?.free_model.?(h.ref, null);
}

test "a model is read through the io and converted with its mesh" {
    var served_io: ServedIo = undefined;
    try served_io.init(triangle_obj);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var model: ?*abi_asset.ke_model_data = null;
    try R.check(h.ref.?.load_model.?(h.ref, "triangle.obj", &model));
    try testing.expect(model != null);
    defer h.ref.?.free_model.?(h.ref, model);

    try testing.expectEqual(@as(u32, 1), model.?.mesh_count);
    try served_io.sub.received(.read_file).atLeast(1);
}

test "an async load runs to completion on the task pool it was given" {
    var served_io: ServedIo = undefined;
    try served_io.init(triangle_obj);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var task_pool = std.mem.zeroes(abi_task_pool.ke_task_pool);
    task_pool.dispatch = &immediateDispatch;

    var result = AsyncResult{ .loader = h.ref };
    const task = h.ref.?.load_model_async.?(h.ref, &task_pool, "triangle.obj", &asyncComplete, &result);

    try testing.expect(task != null);
    try testing.expect(result.done);
    try testing.expect(!result.failed);
}

test "an async load rejects a missing loader task pool or path" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var task_pool = std.mem.zeroes(abi_task_pool.ke_task_pool);
    task_pool.dispatch = &immediateDispatch;

    try testing.expect(h.ref.?.load_model_async.?(null, &task_pool, "test.obj", &asyncComplete, null) == null);
    try testing.expect(h.ref.?.load_model_async.?(h.ref, null, "test.obj", &asyncComplete, null) == null);
    try testing.expect(h.ref.?.load_model_async.?(h.ref, &task_pool, null, &asyncComplete, null) == null);
}

test "an async load rejects a missing completion callback" {
    var served_io: ServedIo = undefined;
    try served_io.init(null);
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var task_pool = std.mem.zeroes(abi_task_pool.ke_task_pool);
    task_pool.dispatch = &immediateDispatch;

    try testing.expect(h.ref.?.load_model_async.?(h.ref, &task_pool, "test.obj", null, null) == null);
}

test "a malformed model file yields a model carrying no meshes" {
    var served_io: ServedIo = undefined;
    try served_io.init("THIS IS NOT VALID OBJ CONTENT\n");
    defer served_io.deinit();
    const h = served_io.loader();
    defer h.destroy.?(h.ref);

    var model: ?*abi_asset.ke_model_data = null;
    try R.check(h.ref.?.load_model.?(h.ref, "malformed.obj", &model));
    try testing.expect(model != null);
    defer h.ref.?.free_model.?(h.ref, model);

    try testing.expectEqual(@as(u32, 0), model.?.mesh_count);
}
