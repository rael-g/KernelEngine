//! Implements the audio contract over a miniaudio engine, with a resource cache deciding how long
//! each loaded sound lives.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_audio_miniaudio").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const ma = @import("c");
const abi_audio = @import("abi_audio");
const abi_io = @import("abi_io");
const abi_resource_cache = @import("abi_resource_cache");
const abi_resource_cache_default_factory = @import("abi_resource_cache_default_factory");
const abi_result = @import("abi_result");

const R = @import("result").Result(.{});

/// One loaded sound, allocated per load and owned by `sounds` until `destroySoundResource` frees
/// it. `bytes` is the file the io read, which `decoder` reads from until it is released through
/// the io; `decoder` is initialised once `decoder_ready` is set and `sound` once `initialized` is.
const LoadedSound = struct {
    sound: ma.ma_sound,
    initialized: bool,
    decoder: ma.ma_decoder,
    decoder_ready: bool,
    bytes: ?*anyopaque,
};

/// The backend's whole state: allocated by `ke_audio_miniaudio_create`, freed by `audioDestroy`,
/// and passed to the cache as the context of `destroySoundResource`. `engine` is uninitialised only
/// when `engine_ready` is set. `cache` and `cache_destroy` are undefined until the cache is
/// created, and the destroy callback reads `sounds`, so the map must still exist while the cache is
/// alive. A sound id is a key of `sounds` and a handle of the cache, which reference-counts it by
/// id and by path. `io` is borrowed from the factory's caller, and every sound file is read through
/// it. Everything runs on the calling thread.
const State = struct {
    io: *abi_io.c.ke_io,
    engine: ma.ma_engine,
    engine_ready: bool,
    sounds: std.AutoHashMap(abi_audio.c.ke_audio_sound, *LoadedSound),
    next_id: abi_audio.c.ke_audio_sound,
    cache: *abi_resource_cache.c.ke_resource_cache,
    cache_destroy: *const fn (?*abi_resource_cache.c.ke_resource_cache) callconv(.c) void,
};

const log = std.log.scoped(.audio_miniaudio);

/// Destroy callback the cache calls when the last reference to an id goes. It removes the slot from
/// `sounds` before freeing it, so the id stops resolving.
fn destroySoundResource(handle: abi_resource_cache.c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(ctx.?));
    const slot: ?*LoadedSound = if (state.sounds.fetchRemove(handle)) |kv| kv.value else null;
    if (slot) |s| release(state, s);
}

fn release(state: *State, s: *LoadedSound) void {
    if (s.initialized) ma.ma_sound_uninit(&s.sound);
    if (s.decoder_ready) _ = ma.ma_decoder_uninit(&s.decoder);
    if (s.bytes) |bytes| state.io.free_bytes.?(state.io, bytes);
    gpa.destroy(s);
}

/// Tears the backend down in the order the cache callback requires: the cache first, which frees
/// every sound still held, then the engine if it was initialised, then the map, the state and the
/// struct. A null backend is ignored.
fn audioDestroy(self: ?*abi_audio.c.ke_audio) callconv(.c) void {
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
fn audioLoadSound(self: ?*abi_audio.c.ke_audio, path: [*c]const u8, out_sound: ?*abi_audio.c.ke_audio_sound) callconv(.c) abi_result.c.ke_result {
    const out = out_sound orelse return R.code(error.InvalidArgument);
    out.* = abi_audio.c.KE_AUDIO_SOUND_INVALID;
    if (self == null or path == null) return R.code(error.InvalidArgument);
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    out.* = loadSound(state, path) catch |err| {
        log.warn("loading {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    return R.ok;
}

fn loadSound(state: *State, path: [*c]const u8) R.Error!abi_audio.c.ke_audio_sound {
    var cached: abi_resource_cache.c.ke_resource_handle = undefined;
    if (state.cache.try_get_cached.?(state.cache, path, &cached))
        return @intCast(cached);

    var request: ?*abi_io.c.ke_io_request = null;
    try R.check(state.io.read_file.?(state.io, path, &request));
    var file: abi_io.c.ke_io_result = undefined;
    R.check(state.io.wait.?(state.io, request, &file)) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return error.NotFound,
    };

    const slot = gpa.create(LoadedSound) catch {
        state.io.free_bytes.?(state.io, file.bytes);
        return error.OutOfMemory;
    };
    slot.* = std.mem.zeroes(LoadedSound);
    slot.bytes = file.bytes;
    errdefer release(state, slot);

    const decoded = ma.ma_decoder_init_memory(file.bytes, @intCast(file.size), null, &slot.decoder);
    if (decoded != ma.MA_SUCCESS) {
        log.warn("{s}: {s}", .{ std.mem.span(path), ma.ma_result_description(decoded) });
        return error.NotFound;
    }
    slot.decoder_ready = true;

    const r = ma.ma_sound_init_from_data_source(&state.engine, @ptrCast(&slot.decoder), 0, null, &slot.sound);
    if (r != ma.MA_SUCCESS) {
        log.warn("{s}: {s}", .{ std.mem.span(path), ma.ma_result_description(r) });
        return error.NotFound;
    }
    slot.initialized = true;

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
fn audioUnloadSound(self: ?*abi_audio.c.ke_audio, id: abi_audio.c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == abi_audio.c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    _ = state.cache.release.?(state.cache, id);
}

/// Resolves an id to its slot, or null when it was never loaded or has been released.
fn findSound(state: *State, id: abi_audio.c.ke_audio_sound) ?*LoadedSound {
    return state.sounds.get(id);
}

/// A sound already playing is restarted from its first frame, with the given volume and looping
/// flag. When the start fails, the sound is left stopped. Fails with an invalid-argument error for
/// a null backend or the invalid id, with a not-found error for an id that is not loaded, and with
/// a general error when miniaudio cannot start the sound.
fn audioPlay(self: ?*abi_audio.c.ke_audio, id: abi_audio.c.ke_audio_sound, volume: f32, loop: bool) callconv(.c) abi_result.c.ke_result {
    if (self == null or id == abi_audio.c.KE_AUDIO_SOUND_INVALID) return R.code(error.InvalidArgument);
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
fn audioStop(self: ?*abi_audio.c.ke_audio, id: abi_audio.c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == abi_audio.c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    if (findSound(state, id)) |s| {
        if (s.initialized) _ = ma.ma_sound_stop(&s.sound);
    }
}

/// Sets the volume of the engine, which scales every sound. A null backend is ignored.
fn audioSetMasterVolume(self: ?*abi_audio.c.ke_audio, volume: f32) callconv(.c) void {
    const api = self orelse return;
    const state: *State = @ptrCast(@alignCast(api.handle));
    _ = ma.ma_engine_set_volume(&state.engine, volume);
}

/// Builds the state, the engine, the cache and the contract struct, in that order, and logs that
/// the backend initialised. Each failure releases the steps before it, so a failed call leaves no
/// engine, cache or state behind and the handle zeroed. Fails with invalid argument for a null io,
/// out of memory on the state or the struct, general when the engine cannot start, and whatever the
/// cache creation returns.
export fn ke_audio_miniaudio_create(io_in: ?*abi_io.c.ke_io, out_audio: ?*abi_audio.c.ke_audio_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_audio orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const io = io_in orelse return R.code(error.InvalidArgument);
    out.* = create(io) catch |err| {
        log.warn("creating the audio backend failed: {t}", .{err});
        return R.code(err);
    };
    log.info("backend initialized", .{});
    return R.ok;
}

fn create(io: *abi_io.c.ke_io) R.Error!abi_audio.c.ke_audio_handle {
    const state = gpa.create(State) catch return error.OutOfMemory;
    errdefer gpa.destroy(state);
    state.* = .{
        .io = io,
        .engine = undefined,
        .engine_ready = false,
        .sounds = std.AutoHashMap(abi_audio.c.ke_audio_sound, *LoadedSound).init(gpa),
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

    var cache_params = abi_resource_cache.c.ke_resource_cache_params{ .destroy_fn = &destroySoundResource, .destroy_ctx = state };
    var cache_h: abi_resource_cache.c.ke_resource_cache_handle = undefined;
    try R.check(abi_resource_cache_default_factory.ke_resource_cache_create(&cache_params, &cache_h));
    state.cache = cache_h.ref.?;
    state.cache_destroy = cache_h.destroy.?;
    errdefer state.cache_destroy(state.cache);

    const api = gpa.create(abi_audio.c.ke_audio) catch return error.OutOfMemory;
    api.* = std.mem.zeroes(abi_audio.c.ke_audio);
    api.handle = state;
    api.load_sound = &audioLoadSound;
    api.unload_sound = &audioUnloadSound;
    api.play = &audioPlay;
    api.stop = &audioStop;
    api.set_master_volume = &audioSetMasterVolume;

    return .{ .ref = api, .destroy = &audioDestroy };
}

const testing = std.testing;

const zsub = @import("zsub");

var served: ?[]const u8 = null;
var request_token: u8 = 0;

fn readServed(args: zsub.For(abi_io.c.ke_io).Args(.read_file)) abi_result.c.ke_result {
    args[2].?.* = @ptrCast(&request_token);
    return R.ok;
}

fn waitServed(args: zsub.For(abi_io.c.ke_io).Args(.wait)) abi_result.c.ke_result {
    const bytes = served orelse return R.code(error.NotFound);
    if (args[2]) |out| {
        out.* = std.mem.zeroes(abi_io.c.ke_io_result);
        out.bytes = @constCast(bytes.ptr);
        out.size = bytes.len;
    }
    return R.ok;
}

fn freeServed(_: zsub.For(abi_io.c.ke_io).Args(.free_bytes)) void {}

var served_io: zsub.For(abi_io.c.ke_io) = undefined;
var served_io_ready = false;

fn serving(bytes: ?[]const u8) !*abi_io.c.ke_io {
    served = bytes;
    if (!served_io_ready) {
        try served_io.init();
        _ = served_io.when(.read_file).does(readServed);
        _ = served_io.when(.wait).does(waitServed);
        _ = served_io.when(.free_bytes).does(freeServed);
        served_io_ready = true;
    }
    return served_io.api();
}

fn createAudio() abi_audio.c.ke_audio_handle {
    var h: abi_audio.c.ke_audio_handle = undefined;
    const io = serving(null) catch return .{ .ref = null, .destroy = null };
    R.check(ke_audio_miniaudio_create(io, &h)) catch return .{ .ref = null, .destroy = null };
    return h;
}

const silent_wav = [_]u8{
    'R', 'I', 'F', 'F', 40, 0, 0, 0, 'W', 'A', 'V', 'E',
    'f', 'm', 't', ' ', 16, 0, 0, 0, 1, 0, 1, 0,
    0x44, 0xac, 0, 0, 0x88, 0x58, 0x01, 0, 2, 0, 16, 0,
    'd', 'a', 't', 'a', 4, 0, 0, 0, 0, 0, 0, 0,
};

test "creating without an io is refused and leaves the handle zeroed" {
    var h: abi_audio.c.ke_audio_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_audio_miniaudio_create(null, &h)));
    try testing.expect(h.ref == null and h.destroy == null);
}

test "a sound is read through the io and decoded from memory" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    _ = try serving(&silent_wav);
    defer served = null;
    var id: abi_audio.c.ke_audio_sound = abi_audio.c.KE_AUDIO_SOUND_INVALID;
    try R.check(h.ref.?.load_sound.?(h.ref, "beep.wav", &id));
    try testing.expect(id != abi_audio.c.KE_AUDIO_SOUND_INVALID);
    try served_io.received(.read_file).atLeast(1);
    h.ref.?.unload_sound.?(h.ref, id);
}

test "bytes that are not a sound are refused as not found" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    _ = try serving("not a sound");
    defer served = null;
    var id: abi_audio.c.ke_audio_sound = 1;
    try testing.expectError(error.NotFound, R.check(h.ref.?.load_sound.?(h.ref, "noise.wav", &id)));
    try testing.expectEqual(@as(abi_audio.c.ke_audio_sound, abi_audio.c.KE_AUDIO_SOUND_INVALID), id);
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

    var id: abi_audio.c.ke_audio_sound = 1;
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.load_sound.?(h.ref, null, &id)));
    try testing.expectEqual(@as(abi_audio.c.ke_audio_sound, abi_audio.c.KE_AUDIO_SOUND_INVALID), id);
}

test "loading a sound the io does not find returns the invalid sound id" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    var id: abi_audio.c.ke_audio_sound = 1;
    try testing.expectError(error.NotFound, R.check(h.ref.?.load_sound.?(h.ref, "nonexistent.wav", &id)));
    try testing.expectEqual(@as(abi_audio.c.ke_audio_sound, abi_audio.c.KE_AUDIO_SOUND_INVALID), id);
}

test "unloading the invalid sound id is a no-op" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    h.ref.?.unload_sound.?(h.ref, abi_audio.c.KE_AUDIO_SOUND_INVALID);
}

test "stopping through a null backend is a no-op" {
    audioStop(null, abi_audio.c.KE_AUDIO_SOUND_INVALID);
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

    try testing.expectError(error.NotFound, R.check(h.ref.?.play.?(h.ref, 12345, 1.0, false)));
}

test "the master volume accepts the full unit range" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    h.ref.?.set_master_volume.?(h.ref, 0.5);
    h.ref.?.set_master_volume.?(h.ref, 0.0);
    h.ref.?.set_master_volume.?(h.ref, 1.0);
}

test "playing through a null backend is an invalid argument" {
    try testing.expectError(error.InvalidArgument, R.check(audioPlay(null, abi_audio.c.KE_AUDIO_SOUND_INVALID, 1.0, false)));
}

test "creating and destroying the audio backend leaves no block allocated" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
