const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

pub const _DllMainCRTStartup = @import("kerror")._DllMainCRTStartup;

const heap = @import("heap");
const gpa = heap.gpa;

const ma = @cImport({
    @cInclude("miniaudio.h");
});

const c = @cImport({
    @cInclude("kernel_engine/audio/miniaudio/miniaudio_audio.h");
    @cInclude("kernel_engine/logger/logger.h");
    @cInclude("kernel_engine/resource_cache/resource_cache.h");
    @cInclude("kernel_engine/resource_cache/default/resource_cache_default_create.h");
});

const E = @import("kerror").Errors(c);

const LoadedSound = struct {
    sound: ma.ma_sound,
    initialized: bool,
};

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
    state.cache_destroy(state.cache);
    if (state.engine_ready) ma.ma_engine_uninit(&state.engine);
    state.sounds.deinit();
    gpa.destroy(state);
    gpa.destroy(api);
}

fn audioLoadSound(self: ?*c.ke_audio, path: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_audio_sound {
    if (self == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_AUDIO_SOUND_INVALID;
    }
    const state: *State = @ptrCast(@alignCast(self.?.handle));

    var cached: c.ke_resource_handle = undefined;
    if (state.cache.try_get_cached.?(state.cache, path, &cached))
        return @intCast(cached);

    const slot = gpa.create(LoadedSound) catch {
        E.fail(out_error, .out_of_memory, "sound slot allocation failed", @src());
        return c.KE_AUDIO_SOUND_INVALID;
    };
    slot.* = std.mem.zeroes(LoadedSound);

    const r = ma.ma_sound_init_from_file(&state.engine, path, 0, null, null, &slot.sound);
    if (r != ma.MA_SUCCESS) {
        logWarn(state.logger, ma.ma_result_description(r));
        gpa.destroy(slot);
        E.fail(out_error, .not_found, "sound file not found or failed to load", @src());
        return c.KE_AUDIO_SOUND_INVALID;
    }
    slot.initialized = true;

    if (state.next_id == 0) state.next_id = 1;
    const id = state.next_id;
    state.next_id += 1;
    state.sounds.put(id, slot) catch {
        ma.ma_sound_uninit(&slot.sound);
        gpa.destroy(slot);
        E.fail(out_error, .out_of_memory, "sound map insert failed", @src());
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
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const state: *State = @ptrCast(@alignCast(self.?.handle));

    const slot = findSound(state, id);
    if (slot == null or !slot.?.initialized) {
        E.fail(out_error, .not_found, "sound not loaded", @src());
        return false;
    }
    const s = slot.?;

    _ = ma.ma_sound_stop(&s.sound);
    _ = ma.ma_sound_seek_to_pcm_frame(&s.sound, 0);
    ma.ma_sound_set_volume(&s.sound, volume);
    ma.ma_sound_set_looping(&s.sound, if (loop != 0) ma.MA_TRUE else ma.MA_FALSE);
    const r = ma.ma_sound_start(&s.sound);
    if (r != ma.MA_SUCCESS) {
        E.fail(out_error, .general, "ma_sound_start failed", @src());
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
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return empty;
    }

    const state = gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
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
        E.fail(out_error, .general, "engine init failed", @src());
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
        E.fail(out_error, .out_of_memory, "api allocation failed", @src());
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

const testing = std.testing;

fn createAudio() c.ke_audio_handle {
    var params = std.mem.zeroes(c.ke_audio_miniaudio_params);
    params.logger = null;
    return ke_audio_miniaudio_create(&params, null);
}

test "creating the backend yields a usable handle when a device is available" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    try testing.expect(h.destroy != null);
}

test "creating the backend with null params returns a null handle" {
    const h = ke_audio_miniaudio_create(null, null);
    try testing.expect(h.ref == null);
}

test "loading a sound with a null path returns the invalid sound id" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    const id = h.ref.*.load_sound.?(h.ref, null, null);
    try testing.expectEqual(@as(c.ke_audio_sound, c.KE_AUDIO_SOUND_INVALID), id);
}

test "loading a sound from a path that does not exist returns the invalid sound id" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    const id = h.ref.*.load_sound.?(h.ref, "nonexistent.wav", null);
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

    const ok = h.ref.*.play.?(h.ref, 12345, 1.0, 0, null);
    try testing.expect(!ok);
}

test "the master volume accepts the full unit range" {
    const h = createAudio();
    if (h.ref == null) return error.SkipZigTest;
    defer h.destroy.?(h.ref);

    h.ref.*.set_master_volume.?(h.ref, 0.5);
    h.ref.*.set_master_volume.?(h.ref, 0.0);
    h.ref.*.set_master_volume.?(h.ref, 1.0);
}

test "playing through a null backend returns false" {
    const ok = audioPlay(null, c.KE_AUDIO_SOUND_INVALID, 1.0, 0, null);
    try testing.expect(!ok);
}
