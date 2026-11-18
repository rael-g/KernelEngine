const std = @import("std");
const testing = std.testing;

const abi_completion = @import("abi_completion");
const abi_ecs = @import("abi_ecs");
const abi_ecs_variant = @import("abi_ecs_variant");
const abi_extraction = @import("abi_extraction");
const abi_module = @import("abi_module");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_scheduler = @import("abi_scheduler");
const heap = @import("heap");
const zsub = @import("zsub");
const R = @import("result").Result(.{});
const extraction = @import("extraction_default.zig");

const e = abi_ecs.c;
const x = abi_extraction.c;
const Entity = e.ke_entity;
const Cid = e.ke_component_id;
const Result = abi_result.c.ke_result;

const Key = struct { entity: Entity, cid: Cid };
const Component = struct { name: []const u8, size: usize, fields: ?[*]const abi_ecs.c.ke_component_field, field_count: u32 };

const World = struct {
    api: e.ke_ecs,
    next_entity: Entity = 100,
    alive: std.AutoHashMapUnmanaged(Entity, void) = .empty,
    components: std.ArrayList(Component) = .empty,
    storage: std.AutoHashMapUnmanaged(Key, []align(8) u8) = .empty,
    queries: std.ArrayList(Cid) = .empty,
    trackers: std.ArrayList(Cid) = .empty,
    lost: std.ArrayList(Key) = .empty,
    resolved: std.ArrayList(Entity) = .empty,

    fn init(w: *World) void {
        w.* = .{ .api = std.mem.zeroes(e.ke_ecs) };
        w.api.handle = w;
        w.api.entity_create = entityCreate;
        w.api.entity_destroy = entityDestroy;
        w.api.component_register = componentRegister;
        w.api.component_lookup = componentLookup;
        w.api.component_meta = componentMeta;
        w.api.component_add = componentAdd;
        w.api.component_remove = componentRemove;
        w.api.component_get = componentGet;
        w.api.component_size = componentSize;
        w.api.query_register = queryRegister;
        w.api.query_resolve = queryResolve;
        w.api.removal_track = removalTrack;
        w.api.removals = removals;
    }

    fn deinit(w: *World) void {
        var it = w.storage.valueIterator();
        while (it.next()) |bytes| testing.allocator.free(bytes.*);
        w.storage.deinit(testing.allocator);
        w.alive.deinit(testing.allocator);
        w.components.deinit(testing.allocator);
        w.queries.deinit(testing.allocator);
        w.trackers.deinit(testing.allocator);
        w.lost.deinit(testing.allocator);
        w.resolved.deinit(testing.allocator);
    }

    fn of(self: ?*e.ke_ecs) *World {
        return @ptrCast(@alignCast(self.?.handle));
    }

    fn register(w: *World, name: []const u8, size: usize, fields: []const abi_ecs.c.ke_component_field) Cid {
        w.components.append(testing.allocator, .{ .name = name, .size = size, .fields = if (fields.len == 0) null else fields.ptr, .field_count = @intCast(fields.len) }) catch return 0;
        return @intCast(w.components.items.len);
    }

    fn has(w: *World, entity: Entity, cid: Cid) bool {
        return w.storage.contains(.{ .entity = entity, .cid = cid });
    }

    fn spawn(w: *World) Entity {
        var entity: Entity = 0;
        _ = entityCreate(&w.api, &entity);
        return entity;
    }

    fn put(w: *World, entity: Entity, cid: Cid, bytes: []const u8) void {
        var data: ?*anyopaque = null;
        _ = componentAdd(&w.api, entity, cid, &data);
        if (data) |d| @memcpy(@as([*]u8, @ptrCast(d))[0..bytes.len], bytes);
    }

    fn get(w: *World, comptime T: type, entity: Entity, cid: Cid) ?*T {
        return @ptrCast(@alignCast(componentGet(&w.api, entity, cid)));
    }

    fn drop(w: *World, key: Key) void {
        const removed = w.storage.fetchRemove(key) orelse return;
        testing.allocator.free(removed.value);
        for (w.trackers.items) |tracked| if (tracked == key.cid) w.lost.append(testing.allocator, key) catch {};
    }

    fn entityCreate(self: ?*e.ke_ecs, out: ?*Entity) callconv(.c) Result {
        const w = of(self);
        w.next_entity += 1;
        w.alive.put(testing.allocator, w.next_entity, {}) catch return R.code(error.OutOfMemory);
        out.?.* = w.next_entity;
        return R.ok;
    }

    fn entityDestroy(self: ?*e.ke_ecs, entity: Entity) callconv(.c) Result {
        const w = of(self);
        _ = w.alive.remove(entity);
        for (1..w.components.items.len + 1) |cid| w.drop(.{ .entity = entity, .cid = @intCast(cid) });
        return R.ok;
    }

    fn componentRegister(self: ?*e.ke_ecs, params: ?*const e.ke_component_desc, out: ?*Cid) callconv(.c) Result {
        const w = of(self);
        out.?.* = w.register(std.mem.span(params.?.name.?), params.?.size, &.{});
        return R.ok;
    }

    fn componentLookup(self: ?*e.ke_ecs, name: ?[*:0]const u8, out: ?*e.ke_component_meta) callconv(.c) bool {
        const w = of(self);
        for (w.components.items, 1..) |c, cid| if (std.mem.eql(u8, c.name, std.mem.span(name.?))) {
            return componentMeta(self, @intCast(cid), out);
        };
        return false;
    }

    fn componentMeta(self: ?*e.ke_ecs, cid: Cid, out: ?*e.ke_component_meta) callconv(.c) bool {
        const w = of(self);
        if (cid == 0 or cid > w.components.items.len) return false;
        const c = w.components.items[cid - 1];
        out.?.* = .{ .cid = cid, .size = c.size, .alignment = 8, .fields = @ptrCast(c.fields), .field_count = c.field_count };
        return true;
    }

    fn componentSize(self: ?*e.ke_ecs, cid: Cid) callconv(.c) usize {
        const w = of(self);
        if (cid == 0 or cid > w.components.items.len) return 0;
        return w.components.items[cid - 1].size;
    }

    fn componentAdd(self: ?*e.ke_ecs, entity: Entity, cid: Cid, out: ?*?*anyopaque) callconv(.c) Result {
        const w = of(self);
        out.?.* = null;
        if (!w.alive.contains(entity)) return R.code(error.InvalidArgument);
        const key: Key = .{ .entity = entity, .cid = cid };
        const slot = w.storage.getOrPut(testing.allocator, key) catch return R.code(error.OutOfMemory);
        if (!slot.found_existing) {
            slot.value_ptr.* = testing.allocator.alignedAlloc(u8, .@"8", componentSize(self, cid)) catch {
                _ = w.storage.remove(key);
                return R.code(error.OutOfMemory);
            };
            @memset(slot.value_ptr.*, 0);
        }
        if (slot.value_ptr.len > 0) out.?.* = slot.value_ptr.ptr;
        return R.ok;
    }

    fn componentRemove(self: ?*e.ke_ecs, entity: Entity, cid: Cid) callconv(.c) Result {
        of(self).drop(.{ .entity = entity, .cid = cid });
        return R.ok;
    }

    fn componentGet(self: ?*e.ke_ecs, entity: Entity, cid: Cid) callconv(.c) ?*anyopaque {
        const bytes = of(self).storage.get(.{ .entity = entity, .cid = cid }) orelse return null;
        return if (bytes.len == 0) null else bytes.ptr;
    }

    fn queryRegister(self: ?*e.ke_ecs, desc: ?*const e.ke_ecs_query_desc, out: ?*e.ke_query_id) callconv(.c) Result {
        const w = of(self);
        w.queries.append(testing.allocator, desc.?.terms.?[0].component) catch return R.code(error.OutOfMemory);
        out.?.* = w.queries.items.len;
        return R.ok;
    }

    fn queryResolve(self: ?*e.ke_ecs, query: e.ke_query_id, segments: ?[*]e.ke_ecs_segment, _: usize, _: ?*?*anyopaque, _: ?*Cid, out_count: ?*usize) callconv(.c) Result {
        const w = of(self);
        const cid = w.queries.items[query - 1];
        w.resolved.clearRetainingCapacity();
        var it = w.storage.keyIterator();
        while (it.next()) |key| if (key.cid == cid) w.resolved.append(testing.allocator, key.entity) catch return R.code(error.OutOfMemory);
        segments.?[0] = .{ .entities = w.resolved.items.ptr, .count = w.resolved.items.len };
        out_count.?.* = 1;
        return R.ok;
    }

    fn removalTrack(self: ?*e.ke_ecs, cid: Cid, out: ?*e.ke_removal_tracker) callconv(.c) Result {
        const w = of(self);
        w.trackers.append(testing.allocator, cid) catch return R.code(error.OutOfMemory);
        out.?.* = cid;
        return R.ok;
    }

    fn removals(self: ?*e.ke_ecs, tracker: e.ke_removal_tracker, out: ?[*]Entity, capacity: usize, out_count: ?*usize) callconv(.c) Result {
        const w = of(self);
        var n: usize = 0;
        var i: usize = 0;
        while (i < w.lost.items.len) {
            if (w.lost.items[i].cid == tracker and n < capacity) {
                out.?[n] = w.lost.items[i].entity;
                n += 1;
                _ = w.lost.orderedRemove(i);
            } else i += 1;
        }
        out_count.?.* = n;
        return R.ok;
    }
};

const Position = extern struct { x: f32, target: Entity };

const position_fields = [_]abi_ecs.c.ke_component_field{
    std.mem.zeroInit(abi_ecs.c.ke_component_field, .{ .name = "x", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = 0, .size = 4 }),
    std.mem.zeroInit(abi_ecs.c.ke_component_field, .{ .name = "target", .type = abi_ecs_variant.c.KE_VARIANT_ENTITY, .offset = @offsetOf(Position, "target"), .size = 8 }),
};

const Fixture = struct {
    main: World = undefined,
    render: World = undefined,
    scheduler: zsub.For(abi_scheduler.c.ke_scheduler) = undefined,
    schedule: zsub.For(abi_schedule.c.ke_schedule) = undefined,
    handle: x.ke_extraction_handle = undefined,
    main_position: Cid = 0,
    render_position: Cid = 0,

    fn init(f: *Fixture) !void {
        f.main.init();
        f.render.init();
        try f.scheduler.init();
        try f.schedule.init();
        f.main_position = f.main.register("position", @sizeOf(Position), &position_fields);
        f.render_position = f.render.register("position", @sizeOf(Position), &position_fields);
        try R.check(extraction_create(f));
    }

    fn extraction_create(f: *Fixture) Result {
        return ke_extraction_create(&f.main.api, &f.render.api, f.scheduler.api(), f.schedule.api(), &f.handle);
    }

    fn deinit(f: *Fixture) void {
        f.handle.destroy.?(f.handle.ref);
        f.schedule.deinit();
        f.scheduler.deinit();
        f.render.deinit();
        f.main.deinit();
    }

    fn ref(f: *Fixture) *x.ke_extraction {
        return f.handle.ref.?;
    }

    fn tagOf(w: *World, name: [*:0]const u8) Cid {
        var meta = std.mem.zeroes(e.ke_component_meta);
        _ = World.componentLookup(&w.api, name, &meta);
        return meta.cid;
    }

    fn synced(f: *Fixture) Entity {
        const entity = f.main.spawn();
        f.main.put(entity, tagOf(&f.main, x.KE_COMPONENT_NAME_RENDER_SYNCED), &.{});
        return entity;
    }

    fn pairOf(f: *Fixture, entity: Entity) !Entity {
        var pair: Entity = 0;
        try R.check(f.ref().render_entity.?(f.ref(), entity, &pair));
        return pair;
    }
};

extern fn ke_extraction_create(?*e.ke_ecs, ?*e.ke_ecs, ?*abi_scheduler.c.ke_scheduler, ?*abi_schedule.c.ke_schedule, ?*x.ke_extraction_handle) Result;
extern fn ke_extraction_history_create(?*x.ke_extraction, ?*abi_module.c.ke_module_handle) Result;

test "a synced entity gets a pair, the pair carries a copy, and the pair goes when the tag does" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try R.check(f.ref().extract_copy.?(f.ref(), f.main_position, f.render_position));
    const entity = f.synced();
    f.main.put(entity, f.main_position, std.mem.asBytes(&Position{ .x = 3, .target = 0 }));
    try R.check(f.ref().extract.?(f.ref(), 0));
    const pair = try f.pairOf(entity);
    var back: Entity = 0;
    try R.check(f.ref().main_entity.?(f.ref(), pair, &back));
    try testing.expectEqual(entity, back);
    try testing.expectEqual(@as(f32, 3), f.render.get(Position, pair, f.render_position).?.x);

    _ = World.componentRemove(&f.main.api, entity, Fixture.tagOf(&f.main, x.KE_COMPONENT_NAME_RENDER_SYNCED));
    try R.check(f.ref().extract.?(f.ref(), 0));
    try testing.expectEqual(R.code(error.NotFound), f.ref().render_entity.?(f.ref(), entity, &back));
    try testing.expect(!f.render.alive.contains(pair));
}

test "an entity carrying a synced component gets a pair without the tag, and loses it with the component" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try R.check(f.ref().sync_component.?(f.ref(), f.main_position));
    try R.check(f.ref().sync_component.?(f.ref(), f.main_position));
    try R.check(f.ref().extract_copy.?(f.ref(), f.main_position, f.render_position));
    try R.check(f.ref().extract_copy.?(f.ref(), f.main_position, f.render_position));
    const entity = f.main.spawn();
    f.main.put(entity, f.main_position, std.mem.asBytes(&Position{ .x = 5, .target = 0 }));
    try R.check(f.ref().extract.?(f.ref(), 0));
    const pair = try f.pairOf(entity);
    try testing.expectEqual(@as(f32, 5), f.render.get(Position, pair, f.render_position).?.x);

    _ = World.componentRemove(&f.main.api, entity, f.main_position);
    try R.check(f.ref().extract.?(f.ref(), 0));
    var back: Entity = 0;
    try testing.expectEqual(R.code(error.NotFound), f.ref().render_entity.?(f.ref(), entity, &back));
    try testing.expect(!f.render.alive.contains(pair));
}

test "an entity field of a copy holds the pair of the entity it names, or the null entity" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try R.check(f.ref().extract_copy.?(f.ref(), f.main_position, f.render_position));
    const a = f.synced();
    const b = f.synced();
    const unsynced = f.main.spawn();
    f.main.put(a, f.main_position, std.mem.asBytes(&Position{ .x = 0, .target = b }));
    f.main.put(b, f.main_position, std.mem.asBytes(&Position{ .x = 0, .target = unsynced }));
    try R.check(f.ref().extract.?(f.ref(), 0));
    try testing.expectEqual(try f.pairOf(b), f.render.get(Position, try f.pairOf(a), f.render_position).?.target);
    try testing.expectEqual(@as(Entity, 0), f.render.get(Position, try f.pairOf(b), f.render_position).?.target);
}

test "a pair loses the copy its entity lost" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try R.check(f.ref().extract_copy.?(f.ref(), f.main_position, f.render_position));
    const entity = f.synced();
    f.main.put(entity, f.main_position, std.mem.asBytes(&Position{ .x = 1, .target = 0 }));
    try R.check(f.ref().extract.?(f.ref(), 0));
    _ = World.componentRemove(&f.main.api, entity, f.main_position);
    try R.check(f.ref().extract.?(f.ref(), 0));
    try testing.expect(!f.render.has(try f.pairOf(entity), f.render_position));
}

test "a copy of components of different sizes is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const small = f.render.register("small", 4, &.{});
    try testing.expectEqual(R.code(error.InvalidArgument), f.ref().extract_copy.?(f.ref(), f.main_position, small));
}

fn blend(_: ?*anyopaque, previous: ?*const anyopaque, current: ?*const anyopaque, alpha: f32, out: ?*anyopaque) callconv(.c) void {
    const p: *const Position = @ptrCast(@alignCast(previous.?));
    const c: *const Position = @ptrCast(@alignCast(current.?));
    const o: *Position = @ptrCast(@alignCast(out.?));
    o.* = .{ .x = p.x + (c.x - p.x) * alpha, .target = c.target };
}

test "an interpolated entity is blended at alpha, a plain one copied, and a teleported one starts from its current value" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const previous = f.main.register("position.previous", @sizeOf(Position), &.{});
    try R.check(f.ref().extract_interpolate.?(f.ref(), f.main_position, previous, f.render_position, blend, null));
    const interpolated = Fixture.tagOf(&f.main, x.KE_COMPONENT_NAME_INTERPOLATED);
    const teleported = Fixture.tagOf(&f.main, x.KE_COMPONENT_NAME_TELEPORTED);
    const moving = f.synced();
    const plain = f.synced();
    f.main.put(moving, interpolated, &.{});
    f.main.put(moving, f.main_position, std.mem.asBytes(&Position{ .x = 10, .target = 0 }));
    f.main.put(plain, f.main_position, std.mem.asBytes(&Position{ .x = 7, .target = 0 }));
    try R.check(f.ref().extract.?(f.ref(), 0.5));
    try testing.expectEqual(@as(f32, 10), f.render.get(Position, try f.pairOf(moving), f.render_position).?.x);

    f.main.get(Position, moving, f.main_position).?.x = 20;
    try R.check(f.ref().extract.?(f.ref(), 0.5));
    try testing.expectEqual(@as(f32, 15), f.render.get(Position, try f.pairOf(moving), f.render_position).?.x);
    try testing.expectEqual(@as(f32, 7), f.render.get(Position, try f.pairOf(plain), f.render_position).?.x);

    f.main.put(moving, teleported, &.{});
    f.main.get(Position, moving, f.main_position).?.x = 100;
    try R.check(f.ref().extract.?(f.ref(), 0.5));
    try testing.expectEqual(@as(f32, 100), f.render.get(Position, try f.pairOf(moving), f.render_position).?.x);
    try testing.expect(!f.main.has(moving, teleported));
}

test "a frame-local render entity is gone at the next extraction" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const temporary = f.render.spawn();
    f.render.put(temporary, Fixture.tagOf(&f.render, x.KE_COMPONENT_NAME_FRAME_LOCAL), &.{});
    try R.check(f.ref().extract.?(f.ref(), 0));
    try testing.expect(!f.render.alive.contains(temporary));
}

var custom_ran: u32 = 0;
fn custom(_: ?*anyopaque, _: ?*x.ke_extraction, _: ?*e.ke_ecs, _: ?*e.ke_ecs) callconv(.c) Result {
    custom_ran += 1;
    return R.ok;
}

test "a custom extraction runs at each extraction, and its failure is the extraction's" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    custom_ran = 0;
    try R.check(f.ref().extract_custom.?(f.ref(), custom, null));
    try R.check(f.ref().extract.?(f.ref(), 0));
    try testing.expectEqual(@as(u32, 1), custom_ran);
    try testing.expectEqual(R.code(error.InvalidArgument), f.ref().extract_custom.?(f.ref(), null, null));
}

test "the render stage extracts at the scheduler's alpha and starts the render schedule's run" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    custom_ran = 0;
    try R.check(f.ref().extract_custom.?(f.ref(), custom, null));
    _ = f.scheduler.when(.fixed_alpha).returns(@as(f32, 0.25));
    var completion: ?*abi_completion.c.ke_completion = null;
    try R.check(f.ref().run.?(f.ref(), 0.016, &completion));
    try testing.expectEqual(@as(u32, 1), custom_ran);
    try f.scheduler.received(.fixed_alpha).times(1);
    try f.schedule.received(.run).times(1);
}

var history_desc: abi_schedule.c.ke_schedule_system_desc = undefined;
fn keepHistory(args: zsub.For(abi_schedule.c.ke_schedule).Args(.register_system)) Result {
    history_desc = args[1].?.*;
    args[2].?.* = 9;
    return R.ok;
}

test "the history module registers one system per interpolation in fixed_pre_update, and detaching removes them" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const previous = f.main.register("position.previous", @sizeOf(Position), &.{});
    try R.check(f.ref().extract_interpolate.?(f.ref(), f.main_position, previous, f.render_position, blend, null));
    var fixed: zsub.For(abi_schedule.c.ke_schedule) = undefined;
    try fixed.init();
    defer fixed.deinit();
    _ = fixed.when(.register_system).does(keepHistory);
    var module: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_extraction_history_create(f.ref(), &module));
    var targets = std.mem.zeroes(abi_module.c.ke_module_targets);
    targets.fixed = @ptrCast(fixed.api());
    targets.fixed_pre_update_set = 4;
    try R.check(module.ref.?.attach.?(module.ref, &targets));
    try testing.expectEqual(@as(abi_schedule.c.ke_schedule_set_id, 4), history_desc.sets.?[0]);
    module.destroy.?(module.ref);
    try fixed.received(.unregister_system).where(zsub.argIs(1, @as(abi_schedule.c.ke_schedule_system_id, 9))).times(1);

    var foreign = std.mem.zeroes(x.ke_extraction);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_extraction_history_create(&foreign, &module));
}

test "creating and destroying extractions leaves no block allocated" {
    var f: Fixture = .{};
    try f.init();
    f.deinit();
    try heap.expectNoLeaks();
}

comptime {
    _ = extraction;
}
