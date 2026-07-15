const std = @import("std");

const gpa = std.heap.c_allocator;

// Declarations only — the implementation is compiled as C from
// miniaudio_impl.c (see build.zig); translate-c cannot reliably lower
// miniaudio's internals, so @cImport never sees MINIAUDIO_IMPLEMENTATION.
const ma = @cImport({
    @cInclude("miniaudio.h");
});

const c = @cImport({
    @cInclude("kernel_engine/audio/miniaudio/miniaudio_audio.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/resource_cache/resource_cache.h");
});

const LoadedSound = struct {
    sound: ma.ma_sound,
    initialized: bool,
};

// Sounds are refcounted and deduped by path through ke_resource_cache — the
// same kernel-built-in primitive the render core owns its texture/mesh/
// material caches through. A second load_sound with the same path returns
// the already-loaded id, retained; the underlying ma_sound is only decoded
// once and only freed at refcount zero. `sounds`/`next_id` are only ever
// touched by the calling thread; miniaudio's hardware-callback thread never
// reaches into this map.
const State = struct {
    logger: ?*c.ke_logger,
    engine: ma.ma_engine,
    engine_ready: bool,
    sounds: std.AutoHashMap(c.ke_audio_sound, *LoadedSound),
    next_id: c.ke_audio_sound,
    cache: *c.ke_resource_cache,
    cache_destroy: *const fn (?*c.ke_resource_cache) callconv(.c) void,
};

fn logWarn(logger: ?*c.ke_logger, msg: [*c]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_WARNING, .tag = "miniaudio", .message = msg };
    lg.log.?(lg, &ev);
}

fn logInfo(logger: ?*c.ke_logger, msg: [*c]const u8) void {
    const lg = logger orelse return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_INFO, .tag = "miniaudio", .message = msg };
    lg.log.?(lg, &ev);
}

// ke_resource_cache destroy_fn: fires at refcount zero (a matching
// unload_sound call, or cache teardown for every still-live sound).
// ctx is the State.
fn destroySoundResource(handle: c.ke_resource_handle, ctx: ?*anyopaque) callconv(.c) void {
    const state: *State = @ptrCast(@alignCast(ctx.?));
    const slot: ?*LoadedSound = if (state.sounds.fetchRemove(handle)) |kv| kv.value else null;
    if (slot) |s| {
        if (s.initialized) ma.ma_sound_uninit(&s.sound);
        gpa.destroy(s);
    }
}

fn audioDestroy(self: ?*c.ke_audio) callconv(.c) void {
    const api = self orelse return;
    const state: *State = @ptrCast(@alignCast(api.handle));
    // Fires destroySoundResource for every sound still referenced, which
    // uninits it and erases it from `sounds` — no separate teardown loop.
    state.cache_destroy(state.cache);
    if (state.engine_ready) ma.ma_engine_uninit(&state.engine);
    state.sounds.deinit();
    gpa.destroy(state);
    gpa.destroy(api);
}

fn audioLoadSound(self: ?*c.ke_audio, path: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_audio_sound {
    if (self == null or path == null) {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src().file, @intCast(@src().line), null);
        return c.KE_AUDIO_SOUND_INVALID;
    }
    const state: *State = @ptrCast(@alignCast(self.?.handle));

    var cached: c.ke_resource_handle = undefined;
    if (state.cache.try_get_cached.?(state.cache, path, &cached))
        return @intCast(cached);

    const slot = gpa.create(LoadedSound) catch {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "sound slot allocation failed", @src().file, @intCast(@src().line), null);
        return c.KE_AUDIO_SOUND_INVALID;
    };
    slot.* = std.mem.zeroes(LoadedSound);

    const r = ma.ma_sound_init_from_file(&state.engine, path, 0, null, null, &slot.sound);
    if (r != ma.MA_SUCCESS) {
        logWarn(state.logger, ma.ma_result_description(r));
        gpa.destroy(slot);
        _ = c.ke_error_set(out_error, &c.KE_ERROR_NOT_FOUND, "sound file not found or failed to load", @src().file, @intCast(@src().line), null);
        return c.KE_AUDIO_SOUND_INVALID;
    }
    slot.initialized = true;

    if (state.next_id == 0) state.next_id = 1; // skip the invalid sentinel
    const id = state.next_id;
    state.next_id += 1;
    state.sounds.put(id, slot) catch {
        ma.ma_sound_uninit(&slot.sound);
        gpa.destroy(slot);
        _ = c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "sound map insert failed", @src().file, @intCast(@src().line), null);
        return c.KE_AUDIO_SOUND_INVALID;
    };
    _ = state.cache.register_resource.?(state.cache, id, null);
    _ = state.cache.cache_insert.?(state.cache, path, id, null);

    return id;
}

fn audioUnloadSound(self: ?*c.ke_audio, id: c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    _ = state.cache.release.?(state.cache, id, null);
}

fn findSound(state: *State, id: c.ke_audio_sound) ?*LoadedSound {
    return state.sounds.get(id);
}

fn audioPlay(self: ?*c.ke_audio, id: c.ke_audio_sound, volume: f32, loop: c.ke_bool, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src().file, @intCast(@src().line), null);
        return false;
    }
    const state: *State = @ptrCast(@alignCast(self.?.handle));

    const slot = findSound(state, id);
    if (slot == null or !slot.?.initialized) {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_NOT_FOUND, "sound not loaded", @src().file, @intCast(@src().line), null);
        return false;
    }
    const s = slot.?;

    // Re-trigger semantics: stop + rewind so play() on an already-playing handle restarts cleanly.
    _ = ma.ma_sound_stop(&s.sound);
    _ = ma.ma_sound_seek_to_pcm_frame(&s.sound, 0);
    ma.ma_sound_set_volume(&s.sound, volume);
    ma.ma_sound_set_looping(&s.sound, if (loop != 0) ma.MA_TRUE else ma.MA_FALSE);
    const r = ma.ma_sound_start(&s.sound);
    if (r != ma.MA_SUCCESS) {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_GENERAL, "ma_sound_start failed", @src().file, @intCast(@src().line), null);
        return false;
    }
    return true;
}

fn audioStop(self: ?*c.ke_audio, id: c.ke_audio_sound) callconv(.c) void {
    if (self == null or id == c.KE_AUDIO_SOUND_INVALID) return;
    const state: *State = @ptrCast(@alignCast(self.?.handle));
    if (findSound(state, id)) |s| {
        if (s.initialized) _ = ma.ma_sound_stop(&s.sound);
    }
}

fn audioSetMasterVolume(self: ?*c.ke_audio, volume: f32) callconv(.c) void {
    const api = self orelse return;
    const state: *State = @ptrCast(@alignCast(api.handle));
    _ = ma.ma_engine_set_volume(&state.engine, volume);
}

export fn ke_audio_miniaudio_create(
    params: [*c]const c.ke_audio_miniaudio_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_audio_handle {
    const empty = c.ke_audio_handle{ .ref = null, .destroy = null };
    if (params == null) {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "invalid argument", @src().file, @intCast(@src().line), null);
        return empty;
    }

    const state = gpa.create(State) catch {
        _ = c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "state allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    state.* = .{
        .logger = params.*.logger,
        .engine = undefined,
        .engine_ready = false,
        .sounds = std.AutoHashMap(c.ke_audio_sound, *LoadedSound).init(gpa),
        .next_id = 1,
        .cache = undefined,
        .cache_destroy = undefined,
    };

    var cfg = ma.ma_engine_config_init();
    const r = ma.ma_engine_init(&cfg, &state.engine);
    if (r != ma.MA_SUCCESS) {
        logWarn(state.logger, ma.ma_result_description(r));
        state.sounds.deinit();
        gpa.destroy(state);
        _ = c.ke_error_set(out_error, &c.KE_ERROR_GENERAL, "engine init failed", @src().file, @intCast(@src().line), null);
        return empty;
    }
    state.engine_ready = true;

    var cache_params = c.ke_resource_cache_params{ .destroy_fn = &destroySoundResource, .destroy_ctx = state };
    const cache_h = c.ke_resource_cache_create(&cache_params, out_error);
    if (cache_h.ref == null) {
        ma.ma_engine_uninit(&state.engine);
        state.sounds.deinit();
        gpa.destroy(state);
        return empty;
    }
    state.cache = cache_h.ref.?;
    state.cache_destroy = cache_h.destroy.?;

    const api = gpa.create(c.ke_audio) catch {
        state.cache_destroy(state.cache);
        ma.ma_engine_uninit(&state.engine);
        state.sounds.deinit();
        gpa.destroy(state);
        _ = c.ke_error_set(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "api allocation failed", @src().file, @intCast(@src().line), null);
        return empty;
    };
    api.* = std.mem.zeroes(c.ke_audio);
    api.handle = state;
    api.load_sound = &audioLoadSound;
    api.unload_sound = &audioUnloadSound;
    api.play = &audioPlay;
    api.stop = &audioStop;
    api.set_master_volume = &audioSetMasterVolume;

    logInfo(state.logger, "miniaudio backend initialized");
    return .{ .ref = api, .destroy = &audioDestroy };
}
