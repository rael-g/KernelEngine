//! The part of an implementation, built from its typed factory: each parameter before the handle is a slot,
//! in order, named by the caller and named after its contract's vtable type, except that a `ke_schedule`
//! followed by a `ke_schedule_set_id` is a hook; a `ke_settings` parameter takes the instance's section; the
//! handle the factory fills is the instance, and a `ke_owner` is one that provides nothing.

const std = @import("std");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");

const c = abi_part.c;

/// A hook of the factory: its name and the set it joins when the composition names none.
pub const Hook = struct {
    name: [:0]const u8,
    default_set: [:0]const u8,
};

/// What a factory cannot say about itself: the implementation's name, one name per dependency parameter and one
/// hook per schedule and set pair, each in the factory's order, which dependencies take none or one instance, the
/// contracts the instance provides besides its handle's, with `provided` giving the vtable of each, and the
/// part's optional functions.
pub const Options = struct {
    name: [:0]const u8,
    slots: []const [:0]const u8,
    hooks: []const Hook = &.{},
    optional: []const [:0]const u8 = &.{},
    also: []const [:0]const u8 = &.{},
    provided: @FieldType(c.ke_part, "provided") = null,
    ready: @FieldType(c.ke_part, "ready") = null,
    pump: @FieldType(c.ke_part, "pump") = null,
    set_log: @FieldType(c.ke_part, "set_log") = null,
};

/// The name of the contract whose vtable type is `T`: its declared name, as "ke_ecs".
pub fn contractName(comptime T: type) [:0]const u8 {
    const full = @typeName(T);
    const at = if (std.mem.lastIndexOfScalar(u8, full, '.')) |i| i + 1 else 0;
    return full[at..] ++ "";
}

/// The part of the implementation `factory` creates, described by `options`.
pub fn of(comptime factory: anytype, comptime options: Options) c.ke_part {
    const Built = Of(factory, options);
    return .{
        .name = options.name.ptr,
        .provides = if (Built.provides.len > 0) &Built.provides[0] else null,
        .provides_count = Built.provides.len,
        .slots = if (Built.slots.len > 0) &Built.slots[0] else null,
        .slot_count = Built.slots.len,
        .hooks = if (Built.hooks.len > 0) &Built.hooks[0] else null,
        .hook_count = Built.hooks.len,
        .create = Built.create,
        .provided = options.provided,
        .ready = options.ready,
        .pump = options.pump,
        .set_log = options.set_log,
    };
}

fn Of(comptime factory: anytype, comptime options: Options) type {
    const params = @typeInfo(@TypeOf(factory)).@"fn".params;
    const Handle = @typeInfo(params[params.len - 1].type.?).optional.child;
    const owner = std.mem.eql(u8, contractName(@typeInfo(Handle).pointer.child), "ke_owner");
    const Settings = ?*abi_settings.c.ke_settings;
    const kinds = kindsOf(params[0 .. params.len - 1], Settings);

    if ((options.also.len > 0) != (options.provided != null)) @compileError(options.name ++ ": a part providing more than its handle's contract says which vtable is each with provided");
    if (owner and options.also.len > 0) @compileError(options.name ++ ": a factory filling a ke_owner provides nothing");
    return struct {
        const provides = blk: {
            if (owner) break :blk [0]?[*:0]const u8{};
            const Pointee = @typeInfo(@typeInfo(@FieldType(@typeInfo(Handle).pointer.child, "ref")).optional.child).pointer.child;
            var all: [1 + options.also.len]?[*:0]const u8 = undefined;
            all[0] = contractName(Pointee).ptr;
            for (options.also, 1..) |name, i| all[i] = name.ptr;
            const final = all;
            break :blk final;
        };

        const hooks = blk: {
            var made: [options.hooks.len]c.ke_part_hook = undefined;
            var at = 0;
            for (kinds) |k| {
                if (k != .hook) continue;
                if (at == options.hooks.len) @compileError(options.name ++ ": the factory has more hooks than hook names");
                made[at] = .{ .name = options.hooks[at].name.ptr, .default_set = options.hooks[at].default_set.ptr };
                at += 1;
            }
            if (at != options.hooks.len) @compileError(options.name ++ ": the factory has fewer hooks than hook names");
            const final = made;
            break :blk final;
        };

        const slots = blk: {
            var made: [options.slots.len]c.ke_part_slot = undefined;
            var at = 0;
            for (params[0 .. params.len - 1], kinds) |p, k| {
                if (k != .slot) continue;
                if (at == options.slots.len) @compileError(options.name ++ ": the factory has more dependencies than slot names");
                const name = options.slots[at];
                made[at] = .{
                    .name = name.ptr,
                    .contract = contractName(@typeInfo(@typeInfo(p.type.?).optional.child).pointer.child).ptr,
                    .cardinality = if (isOptional(name)) c.KE_PART_CARDINALITY_OPTIONAL else c.KE_PART_CARDINALITY_ONE,
                };
                at += 1;
            }
            if (at != options.slots.len) @compileError(options.name ++ ": the factory has fewer dependencies than slot names");
            const final = made;
            break :blk final;
        };

        fn isOptional(comptime name: []const u8) bool {
            for (options.optional) |o| if (std.mem.eql(u8, o, name)) return true;
            return false;
        }

        /// The handle's destroy, the same for every handle the factory fills; kept from the first instance.
        var destroy_of: @FieldType(@typeInfo(Handle).pointer.child, "destroy") = null;

        fn destroy(ref: ?*anyopaque) callconv(.c) void {
            destroy_of.?(@ptrCast(@alignCast(ref)));
        }

        /// Slot `create`. A slot bound to nothing passes null, and each hook its schedule and set; the instance is
        /// left zeroed when the factory fails.
        fn create(self: ?*const c.ke_part, bound: ?*const c.ke_part_bound, hooked: ?*const c.ke_part_hooked, settings: ?*abi_settings.c.ke_settings, out_instance: ?*c.ke_owner) callconv(.c) abi_result.c.ke_result {
            const out = out_instance orelse return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
            out.* = std.mem.zeroes(c.ke_owner);
            if (self == null or (slots.len > 0 and bound == null) or (hooks.len > 0 and hooked == null)) return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
            const each: [*]const c.ke_part_bound = if (bound) |b| @ptrCast(b) else undefined;
            const where: [*]const c.ke_part_hooked = if (hooked) |h| @ptrCast(h) else undefined;
            var handle = std.mem.zeroes(@typeInfo(Handle).pointer.child);
            var args: std.meta.ArgsTuple(@TypeOf(factory)) = undefined;
            comptime var at = 0;
            comptime var hook_at = 0;
            inline for (kinds, 0..) |k, i| switch (k) {
                .settings => args[i] = settings,
                .slot => {
                    const slot = each[at];
                    args[i] = if (slot.count > 0) @ptrCast(@alignCast(@as([*]const ?*anyopaque, @ptrCast(slot.instances))[0])) else null;
                    at += 1;
                },
                .hook => args[i] = @ptrCast(@alignCast(where[hook_at].schedule)),
                .set => {
                    args[i] = where[hook_at].set;
                    hook_at += 1;
                },
            };
            args[params.len - 1] = &handle;
            const result = @call(.auto, factory, args);
            if (result != abi_result.c.KE_OK) return result;
            if (owner) {
                out.* = .{ .ref = handle.ref, .destroy = @ptrCast(handle.destroy) };
                return abi_result.c.KE_OK;
            }
            std.debug.assert(destroy_of == null or destroy_of == handle.destroy);
            destroy_of = handle.destroy;
            out.* = .{ .ref = handle.ref, .destroy = destroy };
            return abi_result.c.KE_OK;
        }
    };
}

const Kind = enum { settings, slot, hook, set };

fn isSchedule(comptime T: type) bool {
    const optional = @typeInfo(T);
    if (optional != .optional) return false;
    const pointer = @typeInfo(optional.optional.child);
    return pointer == .pointer and std.mem.eql(u8, contractName(pointer.pointer.child), "ke_schedule");
}

fn kindsOf(comptime params: []const std.builtin.Type.Fn.Param, comptime Settings: type) [params.len]Kind {
    const SetId = @FieldType(c.ke_part_hooked, "set");
    var kinds: [params.len]Kind = undefined;
    var i = 0;
    while (i < params.len) : (i += 1) {
        const T = params[i].type.?;
        if (T == Settings) {
            kinds[i] = .settings;
        } else if (isSchedule(T) and i + 1 < params.len and params[i + 1].type.? == SetId) {
            kinds[i] = .hook;
            kinds[i + 1] = .set;
            i += 1;
        } else {
            kinds[i] = .slot;
        }
    }
    return kinds;
}

const testing = std.testing;

const ke_gear = extern struct { teeth: u32 };
const ke_wheel = extern struct { gear: ?*ke_gear, spare: ?*ke_gear, size: i64 };
const ke_wheel_handle = extern struct { ref: ?*ke_wheel, destroy: ?*const fn (?*ke_wheel) callconv(.c) void };

var made_wheel: ke_wheel = undefined;
var destroyed: ?*ke_wheel = null;

fn destroyWheel(w: ?*ke_wheel) callconv(.c) void {
    destroyed = w;
}

fn wheelCreate(gear: ?*ke_gear, spare: ?*ke_gear, settings: ?*abi_settings.c.ke_settings, out: ?*ke_wheel_handle) callconv(.c) abi_result.c.ke_result {
    var size: i64 = 0;
    if (settings) |s| _ = s.get_int.?(s, "size", &size);
    if (gear == null) return abi_result.c.KE_RESULT_INVALID_ARGUMENT;
    made_wheel = .{ .gear = gear, .spare = spare, .size = size };
    out.?.* = .{ .ref = &made_wheel, .destroy = destroyWheel };
    return abi_result.c.KE_OK;
}

const wheel_part = of(wheelCreate, .{ .name = "wheel_default", .slots = &.{ "gear", "spare" }, .optional = &.{"spare"} });

fn slotOf(p: c.ke_part, i: usize) c.ke_part_slot {
    const all: [*]const c.ke_part_slot = @ptrCast(p.slots.?);
    return all[i];
}

fn sizeIs(_: ?*abi_settings.c.ke_settings, key: ?[*:0]const u8, out: ?*i64) callconv(.c) abi_result.c.ke_result {
    if (!std.mem.eql(u8, std.mem.span(key.?), "size")) return abi_result.c.KE_RESULT_NOT_FOUND;
    out.?.* = 7;
    return abi_result.c.KE_OK;
}

test "the factory's dependencies become the part's slots, named after their contracts, and its handle what it provides" {
    try testing.expectEqualStrings("wheel_default", std.mem.span(wheel_part.name.?));
    try testing.expectEqual(@as(usize, 1), wheel_part.provides_count);
    try testing.expectEqualStrings("ke_wheel", std.mem.span(wheel_part.provides.?.*.?));
    try testing.expect(wheel_part.provided == null);
    try testing.expectEqual(@as(usize, 2), wheel_part.slot_count);
    try testing.expectEqualStrings("gear", std.mem.span(slotOf(wheel_part, 0).name.?));
    try testing.expectEqualStrings("ke_gear", std.mem.span(slotOf(wheel_part, 0).contract.?));
    try testing.expectEqual(c.KE_PART_CARDINALITY_ONE, slotOf(wheel_part, 0).cardinality);
    try testing.expectEqualStrings("spare", std.mem.span(slotOf(wheel_part, 1).name.?));
    try testing.expectEqual(c.KE_PART_CARDINALITY_OPTIONAL, slotOf(wheel_part, 1).cardinality);
}

test "creating through the part hands the factory the bound instances and the settings, and destroys through the handle" {
    var gear = ke_gear{ .teeth = 12 };
    const gears = [_]?*anyopaque{&gear};
    const bound = [_]c.ke_part_bound{ .{ .instances = @ptrCast(&gears), .count = 1 }, .{ .instances = null, .count = 0 } };
    var settings = std.mem.zeroes(abi_settings.c.ke_settings);
    settings.get_int = sizeIs;
    var instance: c.ke_owner = undefined;
    try testing.expectEqual(abi_result.c.KE_OK, wheel_part.create.?(&wheel_part, &bound[0], null, &settings, &instance));
    const wheel: *ke_wheel = @ptrCast(@alignCast(instance.ref.?));
    try testing.expectEqual(&gear, wheel.gear.?);
    try testing.expect(wheel.spare == null);
    try testing.expectEqual(@as(i64, 7), wheel.size);
    instance.destroy.?(instance.ref);
    try testing.expectEqual(wheel, destroyed.?);
}

const ke_gear_handle = extern struct { ref: ?*ke_gear, destroy: ?*const fn (?*ke_gear) callconv(.c) void };

var made_gear = ke_gear{ .teeth = 3 };

fn gearCreate(out: ?*ke_gear_handle) callconv(.c) abi_result.c.ke_result {
    out.?.* = .{ .ref = &made_gear, .destroy = null };
    return abi_result.c.KE_OK;
}

const gear_part = of(gearCreate, .{ .name = "gear_default", .slots = &.{} });

fn gearAsWheel(instance: ?*anyopaque, index: usize) callconv(.c) ?*anyopaque {
    return if (index == 0) instance else &made_wheel;
}

const gear_and_wheel_part = of(gearCreate, .{ .name = "gear_and_wheel", .slots = &.{}, .also = &.{"ke_wheel"}, .provided = gearAsWheel });

test "a part provides its handle's contract first, then those it names, each vtable given by provided" {
    try testing.expectEqual(@as(usize, 2), gear_and_wheel_part.provides_count);
    const names: [*]const ?[*:0]const u8 = @ptrCast(gear_and_wheel_part.provides.?);
    try testing.expectEqualStrings("ke_gear", std.mem.span(names[0].?));
    try testing.expectEqualStrings("ke_wheel", std.mem.span(names[1].?));
    try testing.expectEqual(@as(?*anyopaque, &made_wheel), gear_and_wheel_part.provided.?(&made_gear, 1));
}

test "a factory with no dependency and no settings is a part with no slot" {
    try testing.expectEqualStrings("ke_gear", std.mem.span(gear_part.provides.?.*.?));
    try testing.expectEqual(@as(usize, 0), gear_part.slot_count);
    try testing.expect(gear_part.slots == null);
    var instance: c.ke_owner = undefined;
    try testing.expectEqual(abi_result.c.KE_OK, gear_part.create.?(&gear_part, null, null, null, &instance));
    try testing.expectEqual(@as(?*anyopaque, &made_gear), instance.ref);
}

test "a factory that fails leaves the instance zeroed and returns its code" {
    const bound = [_]c.ke_part_bound{ .{ .instances = null, .count = 0 }, .{ .instances = null, .count = 0 } };
    var instance: c.ke_owner = undefined;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, wheel_part.create.?(&wheel_part, &bound[0], null, null, &instance));
    try testing.expect(instance.ref == null and instance.destroy == null);
}

const ke_schedule = extern struct { runs: u64 };
const ke_owner = extern struct { ref: ?*anyopaque, destroy: ?*const fn (?*anyopaque) callconv(.c) void };

var hooked_gear: ?*ke_gear = null;
var hooked_to: ?*ke_schedule = null;
var hooked_set: u32 = 0;
var released: ?*anyopaque = null;

fn releaseModule(ref: ?*anyopaque) callconv(.c) void {
    released = ref;
}

fn moduleCreate(gear: ?*ke_gear, tick: ?*ke_schedule, tick_set: u32, out: ?*ke_owner) callconv(.c) abi_result.c.ke_result {
    hooked_gear = gear;
    hooked_to = tick;
    hooked_set = tick_set;
    out.?.* = .{ .ref = &made_gear, .destroy = releaseModule };
    return abi_result.c.KE_OK;
}

const module_part = of(moduleCreate, .{ .name = "gear_module", .slots = &.{"gear"}, .hooks = &.{.{ .name = "tick", .default_set = "update" }} });

test "a schedule followed by a set id is a hook, and a factory filling an owner provides nothing" {
    try testing.expectEqual(@as(usize, 0), module_part.provides_count);
    try testing.expect(module_part.provides == null);
    try testing.expectEqual(@as(usize, 1), module_part.slot_count);
    try testing.expectEqualStrings("ke_gear", std.mem.span(slotOf(module_part, 0).contract.?));
    try testing.expectEqual(@as(usize, 1), module_part.hook_count);
    try testing.expectEqualStrings("tick", std.mem.span(module_part.hooks.?.*.name.?));
    try testing.expectEqualStrings("update", std.mem.span(module_part.hooks.?.*.default_set.?));
}

test "creating a module hands each hook its schedule and set, and the owner is the module's" {
    var gear = ke_gear{ .teeth = 5 };
    var schedule = ke_schedule{ .runs = 0 };
    const gears = [_]?*anyopaque{&gear};
    const bound = [_]c.ke_part_bound{.{ .instances = @ptrCast(&gears), .count = 1 }};
    const hooked = [_]c.ke_part_hooked{.{ .schedule = @ptrCast(&schedule), .set = 4 }};
    var instance: c.ke_owner = undefined;
    try testing.expectEqual(abi_result.c.KE_OK, module_part.create.?(&module_part, &bound[0], &hooked[0], null, &instance));
    try testing.expectEqual(&gear, hooked_gear.?);
    try testing.expectEqual(&schedule, hooked_to.?);
    try testing.expectEqual(@as(u32, 4), hooked_set);
    instance.destroy.?(instance.ref);
    try testing.expectEqual(@as(?*anyopaque, &made_gear), released);
}

test "a part with hooks refuses to create without where they were bound" {
    var gear = ke_gear{ .teeth = 5 };
    const gears = [_]?*anyopaque{&gear};
    const bound = [_]c.ke_part_bound{.{ .instances = @ptrCast(&gears), .count = 1 }};
    var instance: c.ke_owner = undefined;
    try testing.expectEqual(abi_result.c.KE_RESULT_INVALID_ARGUMENT, module_part.create.?(&module_part, &bound[0], null, null, &instance));
    try testing.expect(instance.ref == null);
}
