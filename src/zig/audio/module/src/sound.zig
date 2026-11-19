//! The sound system: keeps the clip of every `ke_sound_component` loaded while its entity holds the
//! component, and keeps a voice playing exactly while the component says it plays.

const std = @import("std");

const abi_audio = @import("abi_audio");
const abi_audio_components = @import("abi_audio_components");
const abi_audio_contract = @import("abi_audio_contract");
const abi_audio_module_factory = @import("abi_audio_module_factory");
const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_module = @import("abi_module");
const abi_schedule = @import("abi_schedule");

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

/// The state behind the `ke_module` handle `ke_sound_create` returns, whose `api.handle` points
/// back at it. The query declaration points into this struct's own term array, so its address stays
/// fixed while the system is registered; `scheduler` is the update schedule while attached. `tracked` holds every clip the module loaded and every voice it started,
/// by entity, and `update` counts the system's runs, so a sound whose entity no longer holds it is
/// found.
const Module = struct {
    api: abi_module.c.ke_module = std.mem.zeroes(abi_module.c.ke_module),
    audio: *abi_audio.c.ke_audio,
    scheduler: ?*abi_schedule.c.ke_schedule = null,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    set: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    tracked: std.AutoHashMapUnmanaged(abi_ecs.c.ke_entity, Tracked) = .empty,
    update: u64 = 0,
    terms: [1]abi_ecs.c.ke_ecs_query_term = undefined,
    queries: [1]abi_ecs.c.ke_ecs_query_desc = undefined,
};

fn moduleOf(user: ?*anyopaque) *Module {
    return @ptrCast(@alignCast(user.?));
}

/// The post-update-phase system. A component whose clip is not loaded and whose path is not empty
/// has it loaded, from its path as written. A voice that reached its end ends the sound; a
/// cleared `playing` stops the voice; a set `playing` without a voice starts one at the component's
/// volume, pitch and looping. A sound ends by clearing `playing`, and its entity is despawned
/// through the context's command queue when its release is when-done; a clip that cannot be loaded
/// or a voice that cannot start ends the sound the same way, and is logged. A tracked sound whose
/// entity no longer holds the component is then stopped and its clip released.
fn soundSystem(ctx: ?*abi_schedule.c.ke_schedule_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
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

fn reconcile(m: *Module, ctx: *abi_schedule.c.ke_schedule_ctx, entity: abi_ecs.c.ke_entity, p: *Sound) void {
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
    if (!(p.pitch > 0)) {
        log.warn("the sound of entity {d} has pitch {d}, which plays nothing; it is ended", .{ entity, p.pitch });
        end(ctx, entity, p);
        return;
    }

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

fn end(ctx: *abi_schedule.c.ke_schedule_ctx, entity: abi_ecs.c.ke_entity, p: *Sound) void {
    p.playing = false;
    if (p.release != abi_audio_components.c.KE_SOUND_RELEASE_WHEN_DONE) return;
    R.check(ctx.commands.?.despawn.?(ctx.commands, entity)) catch |err|
        log.warn("despawning the finished sound of entity {d} failed: {t}", .{ entity, err });
}

fn load(m: *Module, entity: abi_ecs.c.ke_entity, p: *Sound) void {
    const path = std.mem.sliceTo(&p.path, 0);
    if (path.len == 0) return;
    const full = gpa.dupeZ(u8, path) catch return;
    defer gpa.free(full);
    var clip: abi_audio.c.ke_audio_sound = abi_audio.c.KE_AUDIO_SOUND_INVALID;
    R.check(m.audio.load_sound.?(m.audio, full.ptr, &clip)) catch |err| {
        if (err != error.Pending) log.warn("loading {s} failed: {t}", .{ full, err });
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
    gpa.destroy(m);
}

fn moduleOfApi(self: ?*abi_module.c.ke_module) ?*Module {
    return @ptrCast(@alignCast((self orelse return null).handle));
}

/// Slot `attach`: registers the sound system in the update schedule's post_update set.
fn attach(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) abi_result.c.ke_result {
    const m = moduleOfApi(self) orelse return R.code(error.InvalidArgument);
    const targets = targets_in orelse return R.code(error.InvalidArgument);
    if (m.scheduler != null) return R.code(error.NotSupported);
    const sched: *abi_schedule.c.ke_schedule = @ptrCast(targets.update orelse return R.code(error.InvalidArgument));
    m.set = .{targets.post_update_set};
    const desc: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "audio.sound",
        .user_data = m,
        .execute = soundSystem,
        .queries = &m.queries,
        .query_count = m.queries.len,
        .sets = &m.set,
        .set_count = 1,
    };
    R.check(sched.register_system.?(sched, &desc, &m.system)) catch |err| {
        log.warn("attaching the sound module failed: {t}", .{err});
        return R.code(err);
    };
    m.scheduler = sched;
    return R.ok;
}

/// Slot `detach`: unregisters the sound system.
fn detach(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const m = moduleOfApi(self) orelse return;
    const sched = m.scheduler orelse return;
    _ = sched.unregister_system.?(sched, m.system);
    m.scheduler = null;
}

/// The handle's `destroy`: detaches, stops every voice and releases every clip the module holds,
/// and frees the module.
fn destroyHandle(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const m = moduleOfApi(self) orelse return;
    detach(self);
    destroyModule(m);
}

/// Builds the module, its system attached later. A missing ecs or audio fails as an invalid
/// argument; the objects made so far are released on any failure.
export fn ke_sound_create(
    ecs: ?*abi_ecs.c.ke_ecs,
    audio: ?*abi_audio.c.ke_audio,
    out_module: ?*abi_module.c.ke_module_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create(ecs orelse return R.code(error.InvalidArgument), audio orelse return R.code(error.InvalidArgument)) catch |err| {
        log.warn("creating the sound module failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(ecs: *abi_ecs.c.ke_ecs, audio: *abi_audio.c.ke_audio) R.Error!abi_module.c.ke_module_handle {
    const m = try gpa.create(Module);
    m.* = .{ .audio = audio };
    m.api = .{ .handle = m, .attach = attach, .detach = detach };
    errdefer destroyModule(m);

    var cid: abi_ecs.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.c.ke_component_desc{ .name = abi_audio_contract.c.KE_COMPONENT_NAME_SOUND, .size = @sizeOf(Sound), .alignment = @alignOf(Sound), .fields = &abi_audio_contract.c.ke_sound_component_fields, .field_count = abi_audio_contract.c.ke_sound_component_fields.len }, &cid));

    m.terms = .{.{ .component = cid, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }};
    m.queries = .{.{ .terms = &m.terms, .term_count = 1 }};
    return .{ .ref = &m.api, .destroy = destroyHandle };
}

const testing = std.testing;
const zsub = @import("zsub");

const EcsSub = zsub.For(abi_ecs.c.ke_ecs);
const RuntimeSub = zsub.For(abi_schedule.c.ke_schedule);
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

    fn view(_: [*c]abi_schedule.c.ke_schedule_ctx, _: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.c.ke_ecs_segment {
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
    ctx: abi_schedule.c.ke_schedule_ctx,
    m: *Module,

    fn init(h: *Harness) !void {
        FakeAudio.reset();
        h.audio = FakeAudio.api();
        try h.rt.init();
        try h.cmds.init();
        h.ctx = std.mem.zeroes(abi_schedule.c.ke_schedule_ctx);
        h.ctx.view = SoundView.view;
        h.ctx.commands = h.cmds.api();
        h.m = try gpa.create(Module);
        h.m.* = .{ .audio = &h.audio };
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

test "a clip is loaded from its path, as written, on the first update" {
    var h: Harness = undefined;
    try h.init();
    SoundView.author("hit.wav");
    try h.tick();
    try h.tick();
    try testing.expectEqual(@as(usize, 1), FakeAudio.load_count);
    try testing.expectEqualStrings("hit.wav", std.mem.sliceTo(&FakeAudio.loaded[0], 0));
    try testing.expect(SoundView.sounds[0].clip != abi_audio.c.KE_AUDIO_SOUND_INVALID);
    h.deinit();
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
}

test "a playing sound starts one voice at its pitch and keeps it while the voice plays" {
    var h: Harness = undefined;
    try h.init();
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

test "a sound whose pitch is not positive starts no voice and ends" {
    var h: Harness = undefined;
    try h.init();
    defer h.deinit();
    SoundView.author("hit.wav");
    SoundView.sounds[0].playing = true;
    SoundView.sounds[0].pitch = 0;
    try h.tick();
    try h.tick();
    try testing.expectEqual(@as(usize, 0), FakeAudio.started);
    try testing.expect(!SoundView.sounds[0].playing);
}

test "clearing playing stops the voice, and setting it again starts a new one" {
    var h: Harness = undefined;
    try h.init();
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
    try h.init();
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
    try h.init();
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
    try h.init();
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
    try h.init();
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

test "a sound module missing its ecs or audio is refused, and a whole one attached registers one system" {
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

    var h: abi_module.c.ke_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_sound_create(null, &audio, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_sound_create(ecs.api(), null, &h)));
    try testing.expect(h.ref == null);
    try R.check(ke_sound_create(ecs.api(), &audio, &h));
    var targets = std.mem.zeroes(abi_module.c.ke_module_targets);
    try testing.expectError(error.InvalidArgument, R.check(h.ref.?.attach.?(h.ref, &targets)));
    targets.update = @ptrCast(rt.api());
    try R.check(h.ref.?.attach.?(h.ref, &targets));
    try testing.expectError(error.NotSupported, R.check(h.ref.?.attach.?(h.ref, &targets)));
    try rt.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rt.received(.unregister_system).sameAs(rt.received(.register_system));
}
