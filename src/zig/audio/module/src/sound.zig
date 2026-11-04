//! The sound system: keeps the clip of every `ke_sound_component` loaded while its entity holds the
//! component, and keeps a voice playing exactly while the component says it plays.

const std = @import("std");

const abi_audio = @import("abi_audio");
const abi_audio_components = @import("abi_audio_components");
const abi_audio_contract = @import("abi_audio_contract");
const abi_audio_module_factory = @import("abi_audio_module_factory");
const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_runtime = @import("abi_runtime");

const heap = @import("heap");
var gpa = heap.gpa;

const log = std.log.scoped(.sound);
const R = @import("result").Result(.{});

const Sound = abi_audio_components.c.ke_sound_component;

/// A clip the module loaded, the voice playing it, if any, and the update in which its entity was
/// last seen holding it.
const Tracked = struct {
    clip: abi_audio.c.ke_audio_sound,
    voice: abi_audio.c.ke_audio_voice = abi_audio.c.KE_AUDIO_VOICE_INVALID,
    seen: u64,
};

/// The state behind the handle `ke_sound_module_create` returns, owned by that handle. The query
/// declaration points into this struct's own term array, so its address stays fixed while the
/// system is registered. `tracked` holds every clip the module loaded and every voice it started,
/// by entity, and `update` counts the system's runs, so a sound whose entity no longer holds it is
/// found.
const Module = struct {
    audio: *abi_audio.c.ke_audio,
    runtime: *abi_runtime.c.ke_runtime,
    root: ?[]u8 = null,
    system: abi_runtime.c.ke_system_id = 0,
    tracked: std.AutoHashMapUnmanaged(abi_ecs.c.ke_entity, Tracked) = .empty,
    update: u64 = 0,
    terms: [1]abi_runtime.c.ke_component_access = undefined,
    queries: [1]abi_runtime.c.ke_query_decl = undefined,
};

fn moduleOf(user: ?*anyopaque) *Module {
    return @ptrCast(@alignCast(user.?));
}

/// The post-update-phase system. A component whose clip is not loaded and whose path is not empty
/// has it loaded, from the path joined to the root. A voice that reached its end ends the sound; a
/// cleared `playing` stops the voice; a set `playing` without a voice starts one at the component's
/// volume, pitch and looping. A sound ends by clearing `playing`, and its entity is despawned
/// through the context's command queue when its release is when-done; a clip that cannot be loaded
/// or a voice that cannot start ends the sound the same way, and is logged. A tracked sound whose
/// entity no longer holds the component is then stopped and its clip released.
fn soundSystem(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const m = moduleOf(user);
    m.update += 1;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const sounds: [*]Sound = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) reconcile(m, ctx.?, segs.?[s].entities.?[i], &sounds[i]);
    }
    releaseUnseen(m);
    return R.ok;
}

fn reconcile(m: *Module, ctx: *abi_runtime.c.ke_system_ctx, entity: abi_ecs.c.ke_entity, p: *Sound) void {
    if (p.clip == abi_audio.c.KE_AUDIO_SOUND_INVALID) load(m, entity, p);
    const t = m.tracked.getPtr(entity) orelse {
        if (p.playing) end(ctx, entity, p);
        return;
    };
    t.seen = m.update;

    if (t.voice != abi_audio.c.KE_AUDIO_VOICE_INVALID) {
        const finished = !m.audio.voice_playing.?(m.audio, t.voice);
        if (finished or !p.playing) stopVoice(m, t, p);
        if (finished and p.playing) end(ctx, entity, p);
    }
    if (!p.playing or t.voice != abi_audio.c.KE_AUDIO_VOICE_INVALID) return;

    var voice: abi_audio.c.ke_audio_voice = abi_audio.c.KE_AUDIO_VOICE_INVALID;
    R.check(m.audio.voice_start.?(m.audio, t.clip, p.volume, p.pitch, p.loop, &voice)) catch |err| {
        log.warn("starting the sound of entity {d} failed: {t}", .{ entity, err });
        end(ctx, entity, p);
        return;
    };
    t.voice = voice;
    p.voice = voice;
}

fn stopVoice(m: *Module, t: *Tracked, p: *Sound) void {
    m.audio.voice_stop.?(m.audio, t.voice);
    t.voice = abi_audio.c.KE_AUDIO_VOICE_INVALID;
    p.voice = abi_audio.c.KE_AUDIO_VOICE_INVALID;
}

fn end(ctx: *abi_runtime.c.ke_system_ctx, entity: abi_ecs.c.ke_entity, p: *Sound) void {
    p.playing = false;
    if (p.release != abi_audio_components.c.KE_SOUND_RELEASE_WHEN_DONE) return;
    R.check(ctx.commands.?.despawn.?(ctx.commands, entity)) catch |err|
        log.warn("despawning the finished sound of entity {d} failed: {t}", .{ entity, err });
}

fn load(m: *Module, entity: abi_ecs.c.ke_entity, p: *Sound) void {
    const path = std.mem.sliceTo(&p.path, 0);
    if (path.len == 0) return;
    const full = (if (m.root) |root| std.fs.path.joinZ(gpa, &.{ root, path }) else gpa.dupeZ(u8, path)) catch return;
    defer gpa.free(full);
    var clip: abi_audio.c.ke_audio_sound = abi_audio.c.KE_AUDIO_SOUND_INVALID;
    R.check(m.audio.load_sound.?(m.audio, full.ptr, &clip)) catch |err| {
        log.warn("loading {s} failed: {t}", .{ full, err });
        return;
    };
    m.tracked.put(gpa, entity, .{ .clip = clip, .seen = m.update }) catch {
        m.audio.unload_sound.?(m.audio, clip);
        return;
    };
    p.clip = clip;
}

fn release(m: *Module, t: Tracked) void {
    if (t.voice != abi_audio.c.KE_AUDIO_VOICE_INVALID) m.audio.voice_stop.?(m.audio, t.voice);
    m.audio.unload_sound.?(m.audio, t.clip);
}

fn releaseUnseen(m: *Module) void {
    var it = m.tracked.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.seen == m.update) continue;
        release(m, entry.value_ptr.*);
        m.tracked.removeByPtr(entry.key_ptr);
        it = m.tracked.iterator();
    }
}

fn destroyModule(m: *Module) void {
    var it = m.tracked.valueIterator();
    while (it.next()) |t| release(m, t.*);
    m.tracked.deinit(gpa);
    if (m.root) |root| gpa.free(root);
    gpa.destroy(m);
}

/// Unregisters the system, stops every voice and releases every clip the module holds, and frees
/// the module.
fn destroyHandle(self: ?*abi_audio_module_factory.c.ke_sound_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
    _ = m.runtime.unregister_system.?(m.runtime, m.system);
    destroyModule(m);
}

/// Builds the module and registers its system with the runtime given. A missing runtime, ecs or
/// audio fails as an invalid argument; the objects made so far are released on any failure.
export fn ke_sound_module_create(
    runtime: ?*abi_runtime.c.ke_runtime,
    ecs: ?*abi_ecs.c.ke_ecs,
    audio: ?*abi_audio.c.ke_audio,
    config: ?*const abi_audio_module_factory.c.ke_sound_module_config,
    out_module: ?*abi_audio_module_factory.c.ke_sound_module_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create(runtime orelse return R.code(error.InvalidArgument), ecs orelse return R.code(error.InvalidArgument), audio orelse return R.code(error.InvalidArgument), if (config) |c| c.root else null) catch |err| {
        log.warn("creating the sound module failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(rt: *abi_runtime.c.ke_runtime, ecs: *abi_ecs.c.ke_ecs, audio: *abi_audio.c.ke_audio, root: ?[*:0]const u8) R.Error!abi_audio_module_factory.c.ke_sound_module_handle {
    const m = try gpa.create(Module);
    m.* = .{ .audio = audio, .runtime = rt };
    errdefer destroyModule(m);
    if (root) |r| m.root = try gpa.dupe(u8, std.mem.span(r));

    var cid: abi_ecs.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.c.ke_component_params{ .name = abi_audio_contract.c.KE_COMPONENT_NAME_SOUND, .size = @sizeOf(Sound), .alignment = @alignOf(Sound), .fields = &abi_audio_contract.c.ke_sound_component_fields, .field_count = abi_audio_contract.c.ke_sound_component_fields.len }, &cid));

    m.terms = .{.{ .cid = cid, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    m.queries = .{.{ .terms = &m.terms, .term_count = 1 }};
    var sp = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    sp.name = "audio.sound";
    sp.phase = abi_runtime.c.KE_PHASE_POST_UPDATE;
    sp.queries = &m.queries;
    sp.query_count = m.queries.len;
    sp.user_data = m;
    sp.execute = soundSystem;
    try R.check(rt.*.register_system.?(rt, &sp, &m.system));
    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

const testing = std.testing;
const zsub = @import("zsub");

const EcsSub = zsub.For(abi_ecs.c.ke_ecs);
const RuntimeSub = zsub.For(abi_runtime.c.ke_runtime);
const CommandsSub = zsub.For(abi_ecs.c.ke_ecs_commands);

const FakeAudio = struct {
    var loaded: [4][256]u8 = undefined;
    var load_count: usize = 0;
    var unloaded: usize = 0;
    var started: usize = 0;
    var stopped: usize = 0;
    var playing: bool = true;
    var refuses: bool = false;
    var last_pitch: f32 = 0;

    fn reset() void {
        load_count = 0;
        unloaded = 0;
        started = 0;
        stopped = 0;
        playing = true;
        refuses = false;
        last_pitch = 0;
    }

    fn api() abi_audio.c.ke_audio {
        var a = std.mem.zeroes(abi_audio.c.ke_audio);
        a.load_sound = loadSound;
        a.unload_sound = unloadSound;
        a.voice_start = voiceStart;
        a.voice_playing = voicePlaying;
        a.voice_stop = voiceStop;
        return a;
    }

    fn loadSound(_: [*c]abi_audio.c.ke_audio, path: [*c]const u8, out: [*c]abi_audio.c.ke_audio_sound) callconv(.c) abi_result.c.ke_result {
        if (refuses) return R.code(error.NotFound);
        const span = std.mem.span(path);
        @memcpy(loaded[load_count][0..span.len], span);
        loaded[load_count][span.len] = 0;
        load_count += 1;
        out.* = @intCast(load_count);
        return R.ok;
    }

    fn unloadSound(_: [*c]abi_audio.c.ke_audio, _: abi_audio.c.ke_audio_sound) callconv(.c) void {
        unloaded += 1;
    }

    fn voiceStart(_: [*c]abi_audio.c.ke_audio, _: abi_audio.c.ke_audio_sound, _: f32, pitch: f32, _: bool, out: [*c]abi_audio.c.ke_audio_voice) callconv(.c) abi_result.c.ke_result {
        started += 1;
        last_pitch = pitch;
        out.* = @intCast(started);
        return R.ok;
    }

    fn voicePlaying(_: [*c]abi_audio.c.ke_audio, _: abi_audio.c.ke_audio_voice) callconv(.c) bool {
        return playing;
    }

    fn voiceStop(_: [*c]abi_audio.c.ke_audio, _: abi_audio.c.ke_audio_voice) callconv(.c) void {
        stopped += 1;
    }
};

const SoundView = struct {
    var sounds: [1]Sound = undefined;
    var entities: [1]abi_ecs.c.ke_entity = .{5};
    var columns: [1]?*anyopaque = undefined;
    var segment: abi_ecs.c.ke_ecs_segment = undefined;
    var live: usize = 1;

    fn view(_: [*c]abi_runtime.c.ke_system_ctx, _: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.c.ke_ecs_segment {
        segment = std.mem.zeroes(abi_ecs.c.ke_ecs_segment);
        columns = .{&sounds};
        segment.columns = &columns;
        segment.entities = &entities;
        segment.count = live;
        out_count.* = 1;
        return &segment;
    }

    fn author(path: []const u8) void {
        sounds[0] = std.mem.zeroes(Sound);
        @memcpy(sounds[0].path[0..path.len], path);
        sounds[0].volume = 1;
        sounds[0].pitch = 1;
        live = 1;
    }
};

const Harness = struct {
    audio: abi_audio.c.ke_audio,
    rt: RuntimeSub,
    cmds: CommandsSub,
    ctx: abi_runtime.c.ke_system_ctx,
    m: *Module,

    fn init(h: *Harness, root: ?[]const u8) !void {
        FakeAudio.reset();
        h.audio = FakeAudio.api();
        try h.rt.init();
        try h.cmds.init();
        h.ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
        h.ctx.view = SoundView.view;
        h.ctx.commands = h.cmds.api();
        h.m = try gpa.create(Module);
        h.m.* = .{ .audio = &h.audio, .runtime = h.rt.api() };
        if (root) |r| h.m.root = try gpa.dupe(u8, r);
    }

    fn tick(h: *Harness) !void {
        try testing.expect(soundSystem(&h.ctx, h.m, 0) == R.ok);
    }

    fn deinit(h: *Harness) void {
        destroyModule(h.m);
        h.cmds.deinit();
        h.rt.deinit();
    }
};

test "a clip is loaded from its path joined to the root on the first update" {
    var h: Harness = undefined;
    try h.init("base");
    SoundView.author("hit.wav");
    try h.tick();
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.load_count);
    const expected = try std.fs.path.join(testing.allocator, &.{ "base", "hit.wav" });
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, std.mem.sliceTo(&FakeAudio.loaded[0], 0));
    try testing.expect(SoundView.sounds[0].clip != abi_audio.c.KE_AUDIO_SOUND_INVALID);
    h.deinit();
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
}

test "a playing sound starts one voice at its pitch and keeps it while the voice plays" {
    var h: Harness = undefined;
    try h.init(null);
    defer h.deinit();
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    SoundView.sounds[0].pitch = 1.5;
    try h.tick();
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.started);
    try testing.expectEqual(@as(f32, 1.5), FakeAudio.last_pitch);
    try testing.expect(SoundView.sounds[0].playing);
    try testing.expect(SoundView.sounds[0].voice != abi_audio.c.KE_AUDIO_VOICE_INVALID);
}

test "clearing playing stops the voice, and setting it again starts a new one" {
    var h: Harness = undefined;
    try h.init(null);
    defer h.deinit();
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    try h.tick();
    SoundView.sounds[0].playing = false;
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.stopped);
    try testing.expect(SoundView.sounds[0].voice == abi_audio.c.KE_AUDIO_VOICE_INVALID);
    SoundView.sounds[0].playing = true;
    try h.tick();
    try testing.expectEqual(@as(usize, 2), FakeAudio.started);
}

test "a voice that reached its end clears playing and keeps the entity of a kept sound" {
    var h: Harness = undefined;
    try h.init(null);
    defer h.deinit();
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    try h.tick();
    FakeAudio.playing = false;
    try h.tick();
    try testing.expect(!SoundView.sounds[0].playing);
    try testing.expectEqual(@as(usize, 1), FakeAudio.stopped);
    try testing.expectEqual(@as(usize, 1), FakeAudio.started);
    try h.cmds.received(.despawn).never();
}

test "a voice that reached its end despawns the entity of a sound released when done" {
    var h: Harness = undefined;
    try h.init(null);
    defer h.deinit();
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    SoundView.sounds[0].release = abi_audio_components.c.KE_SOUND_RELEASE_WHEN_DONE;
    try h.tick();
    FakeAudio.playing = false;
    try h.tick();
    try h.cmds.received(.despawn).times(1);
    try testing.expectEqual(@as(abi_ecs.c.ke_entity, 5), h.cmds.received(.despawn).lastArgs().?[1]);
}

test "a clip the audio cannot load ends the sound without a voice and is retried" {
    var h: Harness = undefined;
    try h.init(null);
    defer h.deinit();
    FakeAudio.refuses = true;
    SoundView.author("missing.wav");
    SoundView.sounds[0].playing = true;
    SoundView.sounds[0].release = abi_audio_components.c.KE_SOUND_RELEASE_WHEN_DONE;
    try h.tick();
    try testing.expectEqual(@as(usize, 0), FakeAudio.started);
    try testing.expect(!SoundView.sounds[0].playing);
    try h.cmds.received(.despawn).times(1);
    FakeAudio.refuses = false;
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.load_count);
}

test "a sound whose entity no longer holds it is stopped and its clip released on the next update" {
    var h: Harness = undefined;
    try h.init(null);
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    try h.tick();
    SoundView.live = 0;
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.stopped);
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
    h.deinit();
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
}

test "a sound module missing its runtime, ecs or audio is refused, and a whole one registers one system" {
    FakeAudio.reset();
    var audio = FakeAudio.api();
    var ecs: EcsSub = undefined;
    try ecs.init();
    defer ecs.deinit();
    _ = ecs.when(.component_register).writesFresh(2);
    var rt: RuntimeSub = undefined;
    try rt.init();
    defer rt.deinit();
    _ = rt.when(.register_system).writesFresh(2);

    var h: abi_audio_module_factory.c.ke_sound_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_sound_module_create(null, ecs.api(), &audio, null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_sound_module_create(rt.api(), null, &audio, null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_sound_module_create(rt.api(), ecs.api(), null, null, &h)));
    try testing.expect(h.ref == null);
    try R.check(ke_sound_module_create(rt.api(), ecs.api(), &audio, &.{ .root = "base" }, &h));
    try rt.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rt.received(.unregister_system).sameAs(rt.received(.register_system));
}
