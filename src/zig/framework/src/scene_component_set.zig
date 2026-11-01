//! The scene component set: the components the plugins add, registered with an ecs and a world in
//! the order they were added, behind the scene component set vtable.

const abi_asset_resolver = @import("abi_asset_resolver");
const abi_ecs_variant = @import("abi_ecs_variant");
const abi_scene_loader = @import("abi_scene_loader");
const abi_world = @import("abi_world");
const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_framework = @import("abi_framework");
const abi_result = @import("abi_result");
const heap = @import("heap");

const R = @import("result").Result(.{});

const Entry = struct {
    component: abi_ecs.c.ke_component_params,
    apply: abi_framework.c.ke_component_apply_fn,
};

/// One set. `entries` holds the components in the order `add` received them; the names and field
/// tables they point at are borrowed from the plugins that added them.
const State = struct {
    api: abi_framework.c.ke_scene_component_set,
    entries: std.ArrayList(Entry),
};

fn stateOf(self: *abi_framework.c.ke_scene_component_set) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// Slot `add`. Appends a copy of the params and the apply callback; a failed call leaves the set as
/// it was.
fn add(self_in: ?*abi_framework.c.ke_scene_component_set, component: ?*const abi_ecs.c.ke_component_params, apply: abi_framework.c.ke_component_apply_fn) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const params = component orelse return R.code(error.InvalidArgument);
    if (params.name == null) return R.code(error.InvalidArgument);
    const s = stateOf(self);
    s.entries.append(heap.gpa, .{ .component = params.*, .apply = apply }) catch |err| return R.code(err);
    return R.ok;
}

/// Slot `register_into`. Registers the entries in order and stops at the first one the ecs or the
/// world refuses, failing with its code.
fn registerInto(self_in: ?*abi_framework.c.ke_scene_component_set, ecs_in: ?*abi_ecs.c.ke_ecs, world_in: ?*abi_world.c.ke_world) callconv(.c) abi_result.c.ke_result {
    const self = self_in orelse return R.code(error.InvalidArgument);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    const world = world_in orelse return R.code(error.InvalidArgument);
    for (stateOf(self).entries.items) |e| {
        var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
        const made = ecs.component_register.?(ecs, &e.component, &cid);
        if (made != R.ok) return made;
        if (e.component.field_count > 0) {
            const described = world.register_component_fields.?(world, cid, e.component.fields, e.component.field_count);
            if (described != R.ok) return described;
        }
        if (e.apply != null) {
            const applied = world.register_component_apply.?(world, cid, e.apply, null);
            if (applied != R.ok) return applied;
        }
    }
    return R.ok;
}

fn destroy(self_in: ?*abi_framework.c.ke_scene_component_set) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    s.entries.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

/// The factory. On failure the handle is left zeroed.
export fn ke_scene_component_set_create(out_set: ?*abi_framework.c.ke_scene_component_set_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_set orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_framework.c.ke_scene_component_set_handle);
    const s = heap.gpa.create(State) catch |err| return R.code(err);
    s.* = .{ .api = .{ .handle = s, .add = add, .register_into = registerInto }, .entries = .empty };
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const EcsSub = zsub.For(abi_ecs.c.ke_ecs);

fn substituteEcs(ecs: *EcsSub) !void {
    try ecs.init();
    _ = ecs.when(.component_register).writesFresh(2);
}

const FakeWorld = struct {
    api: abi_world.c.ke_world,
    accepts: bool,
    described: [4]abi_asset_resolver.c.ke_component_id = undefined,
    described_count: usize = 0,
    applied: usize = 0,

    fn init(self: *FakeWorld, accepts: bool) void {
        self.* = .{ .api = std.mem.zeroes(abi_world.c.ke_world), .accepts = accepts };
        self.api.handle = self;
        self.api.register_component_fields = &registerComponentFields;
        self.api.register_component_apply = &registerComponentApply;
    }

    fn of(self: ?*abi_world.c.ke_world) *FakeWorld {
        return @ptrCast(@alignCast(self.?.handle));
    }

    fn registerComponentFields(self: ?*abi_world.c.ke_world, cid: abi_asset_resolver.c.ke_component_id, _: ?[*]const abi_ecs.c.ke_component_field, _: u32) callconv(.c) abi_result.c.ke_result {
        const w = of(self);
        if (!w.accepts) return abi_result.c.KE_RESULT_GENERAL;
        w.described[w.described_count] = cid;
        w.described_count += 1;
        return R.ok;
    }

    fn registerComponentApply(self: ?*abi_world.c.ke_world, _: abi_asset_resolver.c.ke_component_id, _: abi_framework.c.ke_component_apply_fn, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
        of(self).applied += 1;
        return R.ok;
    }
};

fn applyNothing(_: ?*anyopaque, _: ?*anyopaque, _: ?[*]abi_ecs_variant.c.ke_variant_table_entry, _: u32) callconv(.c) abi_result.c.ke_result {
    return R.ok;
}

const fields = [_]abi_ecs.c.ke_component_field{.{ .name = "x", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = 0, .size = 4 }};

fn componentParams(name: [*:0]const u8, with_fields: bool) abi_ecs.c.ke_component_params {
    return .{ .name = name, .size = 4, .alignment = 4, .fields = if (with_fields) &fields else null, .field_count = if (with_fields) fields.len else 0 };
}

test "added components are registered in order, their fields and apply callbacks handed to the world" {
    var ecs: EcsSub = undefined;
    try substituteEcs(&ecs);
    defer ecs.deinit();
    var world: FakeWorld = undefined;
    world.init(true);
    var h: abi_framework.c.ke_scene_component_set_handle = undefined;
    try testing.expectEqual(R.ok, ke_scene_component_set_create(&h));
    defer h.destroy.?(h.ref);

    try testing.expectEqual(R.ok, h.ref.?.add.?(h.ref, &componentParams("a", true), null));
    try testing.expectEqual(R.ok, h.ref.?.add.?(h.ref, &componentParams("b", false), applyNothing));
    try testing.expectEqual(R.ok, h.ref.?.add.?(h.ref, &componentParams("c", true), applyNothing));
    try testing.expectEqual(R.ok, h.ref.?.register_into.?(h.ref, ecs.api(), &world.api));

    try testing.expectEqual(@as(usize, 2), world.described_count);
    try testing.expect(world.described[0] < world.described[1]);
    try testing.expectEqual(@as(usize, 2), world.applied);
    try ecs.received(.component_register).times(3);
}

test "a world that refuses the fields fails the registration with its code" {
    var ecs: EcsSub = undefined;
    try substituteEcs(&ecs);
    defer ecs.deinit();
    var world: FakeWorld = undefined;
    world.init(false);
    var h: abi_framework.c.ke_scene_component_set_handle = undefined;
    try testing.expectEqual(R.ok, ke_scene_component_set_create(&h));
    defer h.destroy.?(h.ref);

    try testing.expectEqual(R.ok, h.ref.?.add.?(h.ref, &componentParams("a", true), null));
    try testing.expectEqual(@as(abi_result.c.ke_result, abi_result.c.KE_RESULT_GENERAL), h.ref.?.register_into.?(h.ref, ecs.api(), &world.api));
}

test "a missing set, component, name, ecs, world or out handle is an invalid argument" {
    var ecs: EcsSub = undefined;
    try substituteEcs(&ecs);
    defer ecs.deinit();
    var world: FakeWorld = undefined;
    world.init(true);
    var h: abi_framework.c.ke_scene_component_set_handle = undefined;
    try testing.expectEqual(R.ok, ke_scene_component_set_create(&h));
    defer h.destroy.?(h.ref);

    const invalid: abi_result.c.ke_result = abi_result.c.KE_RESULT_INVALID_ARGUMENT;
    var unnamed = componentParams("a", false);
    unnamed.name = null;
    try testing.expectEqual(invalid, h.ref.?.add.?(null, &componentParams("a", false), null));
    try testing.expectEqual(invalid, h.ref.?.add.?(h.ref, null, null));
    try testing.expectEqual(invalid, h.ref.?.add.?(h.ref, &unnamed, null));
    try testing.expectEqual(invalid, h.ref.?.register_into.?(h.ref, null, &world.api));
    try testing.expectEqual(invalid, h.ref.?.register_into.?(h.ref, ecs.api(), null));
    try testing.expectEqual(invalid, ke_scene_component_set_create(null));
}

test "creating, filling and destroying a set leaves no block allocated" {
    var h: abi_framework.c.ke_scene_component_set_handle = undefined;
    try testing.expectEqual(R.ok, ke_scene_component_set_create(&h));
    try testing.expectEqual(R.ok, h.ref.?.add.?(h.ref, &componentParams("a", true), null));
    h.destroy.?(h.ref);
    try heap.expectNoLeaks();
}
