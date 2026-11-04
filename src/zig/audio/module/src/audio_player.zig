//! The audio player system: keeps the clip of every `ke_audio_player_component` loaded while its
//! entity holds the component, and plays it when the component asks.

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

const log = std.log.scoped(.audio_player);
const R = @import("result").Result(.{});

/// A clip the module loaded, and the update in which its entity was last seen holding it.
const Tracked = struct {
    sound: abi_audio.c.ke_audio_sound,
    seen: u64,
};

/// The state behind the handle `ke_audio_player_module_create` returns, owned by that handle. The
/// query declaration points into this struct's own term array, so its address stays fixed while
/// the system is registered. `tracked` holds every clip the module loaded, by entity, and `update`
/// counts the system's runs, so a clip whose entity no longer holds it is found.
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
/// has it loaded, from the path joined to the root; a requested play plays the loaded clip at the
/// component's volume and clears the request, loaded or not. A clip the audio cannot load, or one
/// the module cannot record, leaves the component without a clip, to be retried on the next
/// update; it is logged and the system still succeeds. A recorded clip whose entity no longer
/// holds it is then unloaded.
fn playerSystem(ctx: ?*abi_runtime.c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const m = moduleOf(user);
    m.update += 1;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const players: [*]abi_audio_components.c.ke_audio_player_component = @ptrCast(@alignCast(segs.?[s].columns.?[0]));
        var i: usize = 0;
        while (i < segs.?[s].count) : (i += 1) {
            const p = &players[i];
            const entity = segs.?[s].entities.?[i];
            if (p.sound == abi_audio.c.KE_AUDIO_SOUND_INVALID) {
                load(m, entity, p);
            } else if (m.tracked.getPtr(entity)) |t| t.seen = m.update;
            if (!p.play_requested) continue;
            p.play_requested = false;
            if (p.sound == abi_audio.c.KE_AUDIO_SOUND_INVALID) continue;
            R.check(m.audio.play.?(m.audio, p.sound, p.volume, false)) catch |err|
                log.warn("playing the clip of entity {d} failed: {t}", .{ entity, err });
        }
    }
    unloadUnseen(m);
    return R.ok;
}

fn load(m: *Module, entity: abi_ecs.c.ke_entity, p: *abi_audio_components.c.ke_audio_player_component) void {
    const path = std.mem.sliceTo(&p.path, 0);
    if (path.len == 0) return;
    const full = (if (m.root) |root| std.fs.path.joinZ(gpa, &.{ root, path }) else gpa.dupeZ(u8, path)) catch return;
    defer gpa.free(full);
    var sound: abi_audio.c.ke_audio_sound = abi_audio.c.KE_AUDIO_SOUND_INVALID;
    R.check(m.audio.load_sound.?(m.audio, full.ptr, &sound)) catch |err| {
        log.warn("loading {s} failed: {t}", .{ full, err });
        return;
    };
    m.tracked.put(gpa, entity, .{ .sound = sound, .seen = m.update }) catch {
        m.audio.unload_sound.?(m.audio, sound);
        return;
    };
    p.sound = sound;
}

fn unloadUnseen(m: *Module) void {
    var it = m.tracked.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.seen == m.update) continue;
        m.audio.unload_sound.?(m.audio, entry.value_ptr.sound);
        m.tracked.removeByPtr(entry.key_ptr);
        it = m.tracked.iterator();
    }
}

fn destroyModule(m: *Module) void {
    var it = m.tracked.valueIterator();
    while (it.next()) |t| m.audio.unload_sound.?(m.audio, t.sound);
    m.tracked.deinit(gpa);
    if (m.root) |root| gpa.free(root);
    gpa.destroy(m);
}

/// Unregisters the system, unloads every clip the module loaded and frees the module.
fn destroyHandle(self: ?*abi_audio_module_factory.c.ke_audio_player_module) callconv(.c) void {
    const m: *Module = @ptrCast(@alignCast(self orelse return));
    _ = m.runtime.unregister_system.?(m.runtime, m.system);
    destroyModule(m);
}

/// Builds the module and registers its system with the runtime given. A missing runtime, ecs or
/// audio fails as an invalid argument; the objects made so far are released on any failure.
export fn ke_audio_player_module_create(
    runtime: ?*abi_runtime.c.ke_runtime,
    ecs: ?*abi_ecs.c.ke_ecs,
    audio: ?*abi_audio.c.ke_audio,
    config: ?*const abi_audio_module_factory.c.ke_audio_player_module_config,
    out_module: ?*abi_audio_module_factory.c.ke_audio_player_module_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    out.* = create(runtime orelse return R.code(error.InvalidArgument), ecs orelse return R.code(error.InvalidArgument), audio orelse return R.code(error.InvalidArgument), if (config) |c| c.root else null) catch |err| {
        log.warn("creating the audio player module failed: {t}", .{err});
        return R.code(err);
    };
    return R.ok;
}

fn create(rt: *abi_runtime.c.ke_runtime, ecs: *abi_ecs.c.ke_ecs, audio: *abi_audio.c.ke_audio, root: ?[*:0]const u8) R.Error!abi_audio_module_factory.c.ke_audio_player_module_handle {
    const m = try gpa.create(Module);
    m.* = .{ .audio = audio, .runtime = rt };
    errdefer destroyModule(m);
    if (root) |r| m.root = try gpa.dupe(u8, std.mem.span(r));

    var cid: abi_ecs.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(ecs.*.component_register.?(ecs, &abi_ecs.c.ke_component_params{ .name = abi_audio_contract.c.KE_COMPONENT_NAME_AUDIO_PLAYER, .size = @sizeOf(abi_audio_components.c.ke_audio_player_component), .alignment = @alignOf(abi_audio_components.c.ke_audio_player_component), .fields = &abi_audio_contract.c.ke_audio_player_component_fields, .field_count = abi_audio_contract.c.ke_audio_player_component_fields.len }, &cid));

    m.terms = .{.{ .cid = cid, .access = abi_runtime.c.KE_ACCESS_WRITE }};
    m.queries = .{.{ .terms = &m.terms, .term_count = 1 }};
    var sp = std.mem.zeroes(abi_runtime.c.ke_runtime_system_params);
    sp.name = "audio.player";
    sp.phase = abi_runtime.c.KE_PHASE_POST_UPDATE;
    sp.queries = &m.queries;
    sp.query_count = m.queries.len;
    sp.user_data = m;
    sp.execute = playerSystem;
    try R.check(rt.*.register_system.?(rt, &sp, &m.system));
    return .{ .ref = @ptrCast(m), .destroy = destroyHandle };
}

const testing = std.testing;
const zsub = @import("zsub");

const EcsSub = zsub.For(abi_ecs.c.ke_ecs);
const RuntimeSub = zsub.For(abi_runtime.c.ke_runtime);

const FakeAudio = struct {
    var loaded: [4][256]u8 = undefined;
    var load_count: usize = 0;
    var unloaded: usize = 0;
    var played: usize = 0;
    var refuses: bool = false;

    fn reset() void {
        load_count = 0;
        unloaded = 0;
        played = 0;
        refuses = false;
    }

    fn api() abi_audio.c.ke_audio {
        var a = std.mem.zeroes(abi_audio.c.ke_audio);
        a.load_sound = loadSound;
        a.unload_sound = unloadSound;
        a.play = play;
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

    fn play(_: [*c]abi_audio.c.ke_audio, _: abi_audio.c.ke_audio_sound, _: f32, _: bool) callconv(.c) abi_result.c.ke_result {
        played += 1;
        return R.ok;
    }
};

const PlayerView = struct {
    var players: [1]abi_audio_components.c.ke_audio_player_component = undefined;
    var entities: [1]abi_ecs.c.ke_entity = .{5};
    var columns: [1]?*anyopaque = undefined;
    var segment: abi_ecs.c.ke_ecs_segment = undefined;
    var live: usize = 1;

    fn view(_: [*c]abi_runtime.c.ke_system_ctx, _: u32, out_count: [*c]usize) callconv(.c) [*c]const abi_ecs.c.ke_ecs_segment {
        segment = std.mem.zeroes(abi_ecs.c.ke_ecs_segment);
        columns = .{&players};
        segment.columns = &columns;
        segment.entities = &entities;
        segment.count = live;
        out_count.* = 1;
        return &segment;
    }

    fn author(path: []const u8) void {
        players[0] = std.mem.zeroes(abi_audio_components.c.ke_audio_player_component);
        @memcpy(players[0].path[0..path.len], path);
        players[0].volume = 1;
        live = 1;
    }
};

fn testModule(audio: *abi_audio.c.ke_audio, rt: *RuntimeSub, root: ?[]const u8) !*Module {
    const m = try gpa.create(Module);
    m.* = .{ .audio = audio, .runtime = rt.api() };
    if (root) |r| m.root = try gpa.dupe(u8, r);
    return m;
}

test "a clip is loaded from its path joined to the root on the first update" {
    FakeAudio.reset();
    var audio = FakeAudio.api();
    var rt: RuntimeSub = undefined;
    try rt.init();
    defer rt.deinit();
    const m = try testModule(&audio, &rt, "base");
    var ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
    ctx.view = PlayerView.view;

    PlayerView.author("hit.wav");
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expectEqual(@as(usize, 1), FakeAudio.load_count);
    const expected = try std.fs.path.join(testing.allocator, &.{ "base", "hit.wav" });
    defer testing.allocator.free(expected);
    try testing.expectEqualStrings(expected, std.mem.sliceTo(&FakeAudio.loaded[0], 0));
    try testing.expect(PlayerView.players[0].sound != abi_audio.c.KE_AUDIO_SOUND_INVALID);

    destroyModule(m);
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
}

test "a requested play plays the clip once and clears the request" {
    FakeAudio.reset();
    var audio = FakeAudio.api();
    var rt: RuntimeSub = undefined;
    try rt.init();
    defer rt.deinit();
    const m = try testModule(&audio, &rt, null);
    var ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
    ctx.view = PlayerView.view;

    PlayerView.author("hit.wav");
    PlayerView.players[0].play_requested = true;
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expectEqual(@as(usize, 1), FakeAudio.played);
    try testing.expect(!PlayerView.players[0].play_requested);

    destroyModule(m);
}

test "a clip the audio cannot load clears the request without playing and is retried" {
    FakeAudio.reset();
    FakeAudio.refuses = true;
    var audio = FakeAudio.api();
    var rt: RuntimeSub = undefined;
    try rt.init();
    defer rt.deinit();
    const m = try testModule(&audio, &rt, null);
    var ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
    ctx.view = PlayerView.view;

    PlayerView.author("missing.wav");
    PlayerView.players[0].play_requested = true;
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expectEqual(@as(usize, 0), FakeAudio.played);
    try testing.expect(!PlayerView.players[0].play_requested);

    FakeAudio.refuses = false;
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expectEqual(@as(usize, 1), FakeAudio.load_count);

    destroyModule(m);
}

test "a clip whose entity no longer holds it is unloaded on the next update" {
    FakeAudio.reset();
    var audio = FakeAudio.api();
    var rt: RuntimeSub = undefined;
    try rt.init();
    defer rt.deinit();
    const m = try testModule(&audio, &rt, null);
    var ctx = std.mem.zeroes(abi_runtime.c.ke_system_ctx);
    ctx.view = PlayerView.view;

    PlayerView.author("hit.wav");
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    PlayerView.live = 0;
    try testing.expect(playerSystem(&ctx, m, 0) == R.ok);
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);

    destroyModule(m);
    try testing.expectEqual(@as(usize, 1), FakeAudio.unloaded);
}

test "an audio player module missing its runtime, ecs or audio is refused, and a whole one registers one system" {
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

    var h: abi_audio_module_factory.c.ke_audio_player_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_audio_player_module_create(null, ecs.api(), &audio, null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_audio_player_module_create(rt.api(), null, &audio, null, &h)));
    try testing.expectError(error.InvalidArgument, R.check(ke_audio_player_module_create(rt.api(), ecs.api(), null, null, &h)));
    try testing.expect(h.ref == null);
    try R.check(ke_audio_player_module_create(rt.api(), ecs.api(), &audio, &.{ .root = "base" }, &h));
    try rt.received(.register_system).times(1);
    h.destroy.?(h.ref);
    try rt.received(.unregister_system).sameAs(rt.received(.register_system));
}
