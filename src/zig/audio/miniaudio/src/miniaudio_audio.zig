//! Implements the audio contract over a miniaudio engine, with a resource cache deciding how long
//! each loaded sound lives.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_miniaudio").logFn };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const ma = @import("c");

const c = @import("c");

const R = @import("result").Result(c, .{});

/// One loaded sound, allocated per load and owned by `sounds` until `destroySoundResource` frees
/// it. `sound` is uninitialised only when `initialized` is set, which happens once the file has
/// opened.
const LoadedSound = struct {
    sound: ma.ma_sound,
    initialized: bool,
};

/// The backend's whole state: allocated by `ke_audio_miniaudio_create`, freed by `audioDestroy`,
/// and passed to the cache as the context of `destroySoundResource`. `engine` is uninitialised only
/// when `engine_ready` is set. `cache` and `cache_destroy` are undefined until the cache is
/// created, and the destroy callback reads `sounds`, so the map must still exist while the cache is
/// alive. A sound id is a key of `sounds` and a handle of the cache, which reference-counts it by
/// id and by path. Everything runs on the calling thread.
const State = struct {
    engine: ma.ma_engine,
    engine_ready: bool,
    sounds: std.AutoHashMap(c.ke_audio_sound, *LoadedSound),
    next_id: c.ke_audio_sound,
    cache: *c.ke_resource_cache,
    cache_destroy: *const fn (?*c.ke_resource_cache) callconv(.c) void,
};

const log = std.log.scoped(.audio_miniaudio);

/// Destroy callback the cache calls when the last reference to an id goes. It removes the slot from
/// `sounds` before freeing it, so the id stops resolving.
fn destroySoundResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(ctx.?));
    const slot: ?*LoadedSound = if (state.sounds.fetchRemove(handle)) |kv| kv.value else null;
    if (slot) |s| {
        if (s.initialized) ma.ma_sound_uninit(&s.sound);
        gpa.destroy(s);
    }
}

/// Tears the backend down in the order the cache callback requires: the cache first, which frees
/// every sound still held, then the engine if it was initialised, then the map, the state and the
/// struct. A null backend is ignored.
fn audioDestroy(self: ?*c.ke_audio) callconv(.c) void {
    const api = self orelse return;
    const state: *State = @ptrCast(@alignCast(api.handle));
    state.cache_destroy(state.cache);
    if (state.engine_ready) ma.ma_engine_uninit(&state.engine);
    state.sounds.deinit();
    gpa.destroy(state);
    gpa.destroy(api);
}

/// Writes the id the cache already holds for the path, with one more reference, or a new id that
/// starts with one reference: a new path is opened, stored under a fresh id and registered with
/// the cache by id and by path. The caller gives that reference back through `audioUnloadSound`.
/// On failure the id is the invalid one and no slot is left in the map: invalid argument for a
/// null backend, path or out-parameter, out of memory for the slot or the map entry, and not found
/// when miniaudio cannot open the file.
fn audioLoadSound(self: ?*c.ke_audio, path: [*c]const u8, out_sound: ?*c.ke_audio_sound) callconv(.c) c.ke_result {
    const out = out_sound orelse return R.code(error.InvalidArgument);
    out.* = c.KE_AUDIO_SOUND_INVALID;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    out.* = loadSound(state, path) catch |err| {
        log.warn("loading {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    return R.ok;
}

fn loadSound(state: *State, path: [*c]const u8) R.Error!c.ke_audio_sound {
    var cached: c.ke_resource_handle = undefined;
    if (state.cache.try_get_cached.?(state.cache, path, &cached))
        return @intCast(cached);

    const slot = gpa.create(LoadedSound) catch return error.OutOfMemory;
    errdefer gpa.destroy(slot);
    slot.* = std.mem.zeroes(LoadedSound);

    const r = ma.ma_sound_init_from_file(&state.engine, path, 0, null, null, &slot.sound);
    if (r != ma.MA_SUCCESS) {
        log.warn("{s}: {s}", .{ std.mem.span(path), ma.ma_result_description(r) });
        return error.NotFound;
    }
    slot.initialized = true;
    errdefer ma.ma_sound_uninit(&slot.sound);

    if (state.next_id == 0) state.next_id = 1;
    const id = state.next_id;
    state.next_id += 1;
    state.sounds.put(id, slot) catch return error.OutOfMemory;
    _ = state.cache.register_resource.?(state.cache, id);
    _ = state.cache.cache_insert.?(state.cache, path, id);

    return id;
}

/// Gives back one reference on the id to the cache, which frees the sound when none remain; an id
/// whose last reference went stops resolving. A null
/// backend or the invalid id is ignored.
fn audioUnloadSound(self: ?*c.ke_audio, id: c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    _ = state.cache.release.?(state.cache, id);
}

/// Resolves an id to its slot, or null when it was never loaded or has been released.
fn findSound(state: *State, id: c.ke_audio_sound) ?*LoadedSound {
    return state.sounds.get(id);
}

/// A sound already playing is restarted from its first frame, with the given volume and looping
/// flag. When the start fails, the sound is left stopped. Fails with an invalid-argument error for
/// a null backend or the invalid id, with a not-found error for an id that is not loaded, and with
/// a general error when miniaudio cannot start the sound.
fn audioPlay(self: ?*c.ke_audio, id: c.ke_audio_sound, volume: f32, loop: bool) callconv(.c) c.ke_result {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) return R.code(error.InvalidArgument);
    const state: *State = @ptrCast(@alignCast(self.?.handle));

    const slot = findSound(state, id);
    if (slot == null or !slot.?.initialized) return R.code(error.NotFound);
    const s = slot.?;

    _ = ma.ma_sound_stop(&s.sound);
    _ = ma.ma_sound_seek_to_pcm_frame(&s.sound, 0);
    ma.ma_sound_set_volume(&s.sound, volume);
    ma.ma_sound_set_looping(&s.sound, if (loop) ma.MA_TRUE else ma.MA_FALSE);
    const r = ma.ma_sound_start(&s.sound);
    if (r != ma.MA_SUCCESS) {
        log.warn("starting sound {d} failed: {s}", .{ id, ma.ma_result_description(r) });
        return R.code(error.General);
    }
    return R.ok;
}

/// Stops the sound without releasing it. A null backend, the invalid id or an unknown id is
/// ignored.
fn audioStop(self: ?*c.ke_audio, id: c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    if (findSound(state, id)) |s| {
        if (s.initialized) _ = ma.ma_sound_stop(&s.sound);
    }
}

/// Sets the volume of the engine, which scales every sound. A null backend is ignored.
fn audioSetMasterVolume(self: ?*c.ke_audio, volume: f32) callconv(.c) void {
    const api = self orelse return;
    const state: *State = @ptrCast(@alignCast(api.handle));
    _ = ma.ma_engine_set_volume(&state.engine, volume);
}

/// Builds the state, the engine, the cache and the contract struct, in that order, and logs that
/// the backend initialised. Each failure releases the steps before it, so a failed call leaves no
/// engine, cache or state behind and the handle zeroed. Fails with out of memory on the state or the
/// struct, general when the engine cannot start, and whatever the cache creation returns.
export fn ke_audio_miniaudio_create(out_audio: ?*c.ke_audio_handle) callconv(.c) c.ke_result {
    const out = out_audio orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create() catch |err| {
        log.warn("creating the audio backend failed: {t}", .{err});
        return R.code(err);
    };
    log.info("backend initialized", .{});
    return R.ok;
}

fn create() R.Error!c.ke_audio_handle {
    const state = gpa.create(State) catch return error.OutOfMemory;
    errdefer gpa.destroy(state);
    state.* = .{
        .engine = undefined,
        .engine_ready = false,
        .sounds = std.AutoHashMap(c.ke_audio_sound, *LoadedSound).init(gpa),
        .next_id = 1,
        .cache = undefined,
        .cache_destroy = undefined,
    };
    errdefer state.sounds.deinit();

    var cfg = ma.ma_engine_config_init();
    const r = ma.ma_engine_init(&cfg, &state.engine);
    if (r != ma.MA_SUCCESS) {
        log.warn("the engine did not start: {s}", .{ma.ma_result_description(r)});
        return error.General;
    }
    state.engine_ready = true;
    errdefer ma.ma_engine_uninit(&state.engine);

    var cache_params = c.ke_resource_cache_params{ .destroy_fn = &destroySoundResource, .destroy_ctx = state };
    var cache_h: c.ke_resource_cache_handle = undefined;
    try R.check(c.ke_resource_cache_create(&cache_params, &cache_h));
    state.cache = cache_h.ref.?;
    state.cache_destroy = cache_h.destroy.?;
    errdefer state.cache_destroy(state.cache);

    const api = gpa.create(c.ke_audio) catch return error.OutOfMemory;
    api.* = std.mem.zeroes(c.ke_audio);
    api.handle = state;
    api.load_sound = &audioLoadSound;
    api.unload_sound = &audioUnloadSound;
    api.play = &audioPlay;
    api.stop = &audioStop;
    api.set_master_volume = &audioSetMasterVolume;

    return .{ .ref = api, .destroy = &audioDestroy };
}

const testing = std.testing;

fn createAudio() c.ke_audio_handle {
    var h: c.ke_audio_handle = undefined;
    R.check(ke_audio_miniaudio_create(&h)) catch return .{ .ref = null, .destroy = null };
    return h;
}

test "creating the backend yields a usable handle when a device is available" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    try testing.expect(h.destroy != null);
}

test "loading a sound with a null path returns the invalid sound id" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    var id: c.ke_audio_sound = 1;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.*.load_sound.?(h.ref, null, &id)));
    try testing.expectEqual(@as(c.ke_audio_sound, c.KE_AUDIO_SOUND_INVALID), id);
}

test "loading a sound from a path that does not exist returns the invalid sound id" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    var id: c.ke_audio_sound = 1;
    try testing.expectError(error.NotFound, R.check(h.ref.*.load_sound.?(h.ref, "nonexistent.wav", &id)));
    try testing.expectEqual(@as(c.ke_audio_sound, c.KE_AUDIO_SOUND_INVALID), id);
}

test "unloading the invalid sound id is a no-op" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    h.ref.*.unload_sound.?(h.ref, c.KE_AUDIO_SOUND_INVALID);
}

test "stopping through a null backend is a no-op" {
    audioStop(null, c.KE_AUDIO_SOUND_INVALID);
}

test "setting the master volume through a null backend is a no-op" {
    audioSetMasterVolume(null, 1.0);
}

test "destroying a null backend is a no-op" {
    audioDestroy(null);
}

test "playing a sound that was never loaded fails" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    try testing.expectError(error.NotFound, R.check(h.ref.*.play.?(h.ref, 12345, 1.0, false)));
}

test "the master volume accepts the full unit range" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    h.ref.*.set_master_volume.?(h.ref, 0.5);
    h.ref.*.set_master_volume.?(h.ref, 0.0);
    h.ref.*.set_master_volume.?(h.ref, 1.0);
}

test "playing through a null backend is an invalid argument" {
    try testing.expectError(error.InvalidArgument, R.check(audioPlay(null, c.KE_AUDIO_SOUND_INVALID, 1.0, false)));
}

test "creating and destroying the audio backend leaves no block allocated" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
