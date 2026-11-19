//! The `ke_assembly` contract on the calling thread: a composition is gathered by name, resolved whole before
//! anything is created, then created in dependency order one instance at a time, waiting on each that becomes
//! usable later, and destroyed in the reverse of that order.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_assembly_default").logFn };

pub const _DllMainCRTStartup = @import("dll_entry")._DllMainCRTStartup;

const abi_assembly = @import("abi_assembly");
const abi_assembly_default_factory = @import("abi_assembly_default_factory");
const abi_completion = @import("abi_completion");
const abi_configuration = @import("abi_configuration");
const abi_logger = @import("abi_logger");
const abi_part = @import("abi_part");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_settings = @import("abi_settings");
const heap = @import("heap");

const R = @import("result").Result(.{.{ error.Unresolved, abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED }});
const log = std.log.scoped(.assembly_default);
const gpa = heap.gpa;

const P = abi_part.c;
const A = abi_assembly.c;
const Name = [:0]const u8;
const schedule_contract = "ke_schedule";

const Binding = struct { slot: Name, target: Name };
const Hooking = struct { hook: Name, schedule: Name, set: ?Name };
const Order = struct { slot: Name, first: Name, then: Name };
const SetOrder = struct { first: Name, then: Name };

/// One instance of the composition: of a part, or made outside. After resolve, `slots` holds the instances each
/// slot takes and `hooked` where each hook runs; `made` is set once created, and an external one never is.
const Instance = struct {
    name: Name,
    part_name: ?Name = null,
    section: ?Name = null,
    contract: ?Name = null,
    external: ?*anyopaque = null,
    part: ?*const P.ke_part = null,
    bindings: std.ArrayListUnmanaged(Binding) = .empty,
    hookings: std.ArrayListUnmanaged(Hooking) = .empty,
    orders: std.ArrayListUnmanaged(Order) = .empty,
    slots: [][]usize = &.{},
    hooked: []Hooked = &.{},
    made: ?P.ke_part_instance = null,

    fn provides(self: *const Instance) ?[]const u8 {
        if (self.contract) |c| return c;
        const part = self.part orelse return null;
        return if (part.provides) |p| std.mem.span(p) else null;
    }
};

const Hooked = struct { schedule: usize, set: Name };

/// The sets one schedule instance gets: those the composition and the parts hooked to it introduce, their orders,
/// and, once the schedule is made, their ids.
const Sets = struct {
    names: std.ArrayListUnmanaged(Name) = .empty,
    orders: std.ArrayListUnmanaged(SetOrder) = .empty,
    ids: std.StringHashMapUnmanaged(abi_schedule.c.ke_schedule_set_id) = .empty,
};

/// The state behind the handle: the composition as gathered, then, once resolved, the order instances are made in,
/// how far making has come, and the completion the next instance waits on.
const State = struct {
    api: A.ke_assembly,
    configuration: *abi_configuration.c.ke_configuration,
    log_callback: P.ke_log_callback = null,
    log_ctx: ?*anyopaque = null,
    arena: std.heap.ArenaAllocator,
    parts: std.StringHashMapUnmanaged(*const P.ke_part) = .empty,
    instances: std.ArrayListUnmanaged(Instance) = .empty,
    by_name: std.StringHashMapUnmanaged(usize) = .empty,
    defaults: std.StringHashMapUnmanaged(Name) = .empty,
    sets: std.StringHashMapUnmanaged(Sets) = .empty,
    resolved: bool = false,
    plan: []usize = &.{},
    next: usize = 0,
    waiting: ?*abi_completion.c.ke_completion = null,

    fn names(s: *State) std.mem.Allocator {
        return s.arena.allocator();
    }

    fn copy(s: *State, text: ?[*:0]const u8) R.Error!Name {
        return try s.names().dupeZ(u8, std.mem.span(text orelse return error.InvalidArgument));
    }

    fn instanceOf(s: *State, name: []const u8) ?*Instance {
        return &s.instances.items[s.by_name.get(name) orelse return null];
    }

    fn setsOf(s: *State, schedule: Name) R.Error!*Sets {
        const entry = try s.sets.getOrPut(s.names(), schedule);
        if (!entry.found_existing) entry.value_ptr.* = .{};
        return entry.value_ptr;
    }
};

fn stateOf(self: ?*A.ke_assembly) ?*State {
    const api = self orelse return null;
    return @fieldParentPtr("api", api);
}

fn gathering(self: ?*A.ke_assembly) R.Error!*State {
    const s = stateOf(self) orelse return error.InvalidArgument;
    if (s.resolved) return error.NotSupported;
    return s;
}

fn code(result: R.Error!void) abi_result.c.ke_result {
    result catch |err| return R.code(err);
    return R.ok;
}

/// Slot `route_log`.
fn routeLog(self: ?*A.ke_assembly, callback: P.ke_log_callback, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        s.log_callback = callback orelse break :blk error.InvalidArgument;
        s.log_ctx = ctx;
    });
}

/// Slot `add_part`.
fn addPart(self: ?*A.ke_assembly, part_in: ?*const P.ke_part) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const part = part_in orelse break :blk error.InvalidArgument;
        const name = std.mem.span(part.name orelse break :blk error.InvalidArgument);
        const entry = s.parts.getOrPut(s.names(), name) catch |err| break :blk err;
        if (entry.found_existing) break :blk error.AlreadyExists;
        entry.value_ptr.* = part;
    });
}

fn declare(s: *State, instance: Instance) R.Error!void {
    const entry = try s.by_name.getOrPut(s.names(), instance.name);
    if (entry.found_existing) return error.AlreadyExists;
    entry.value_ptr.* = s.instances.items.len;
    try s.instances.append(s.names(), instance);
}

/// Slot `add_instance`.
fn addInstance(self: ?*A.ke_assembly, name: ?[*:0]const u8, part: ?[*:0]const u8, section: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        break :blk declare(s, .{ .name = s.copy(name) catch |err| break :blk err, .part_name = s.copy(part) catch |err| break :blk err, .section = s.copy(section) catch |err| break :blk err });
    });
}

/// Slot `add_external`.
fn addExternal(self: ?*A.ke_assembly, name: ?[*:0]const u8, contract: ?[*:0]const u8, instance: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const ref = instance orelse break :blk error.InvalidArgument;
        break :blk declare(s, .{ .name = s.copy(name) catch |err| break :blk err, .contract = s.copy(contract) catch |err| break :blk err, .external = ref });
    });
}

fn declared(s: *State, name: ?[*:0]const u8) R.Error!*Instance {
    const n = std.mem.span(name orelse return error.InvalidArgument);
    return s.instanceOf(n) orelse {
        const copied = try s.copy(name);
        try declare(s, .{ .name = copied });
        return s.instanceOf(n).?;
    };
}

/// Slot `bind`. An instance not yet declared is remembered by name and reported by resolve if it never is.
fn bind(self: ?*A.ke_assembly, instance: ?[*:0]const u8, slot: ?[*:0]const u8, target: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const binding = Binding{ .slot = s.copy(slot) catch |err| break :blk err, .target = s.copy(target) catch |err| break :blk err };
        const at = declared(s, instance) catch |err| break :blk err;
        break :blk at.bindings.append(s.names(), binding);
    });
}

/// Slot `hook`.
fn hook(self: ?*A.ke_assembly, instance: ?[*:0]const u8, hook_name: ?[*:0]const u8, schedule: ?[*:0]const u8, set: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const hooking = Hooking{
            .hook = s.copy(hook_name) catch |err| break :blk err,
            .schedule = s.copy(schedule) catch |err| break :blk err,
            .set = if (set != null) s.copy(set) catch |err| break :blk err else null,
        };
        const at = declared(s, instance) catch |err| break :blk err;
        break :blk at.hookings.append(s.names(), hooking);
    });
}

/// Slot `order`.
fn order(self: ?*A.ke_assembly, instance: ?[*:0]const u8, slot: ?[*:0]const u8, first: ?[*:0]const u8, then: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const o = Order{ .slot = s.copy(slot) catch |err| break :blk err, .first = s.copy(first) catch |err| break :blk err, .then = s.copy(then) catch |err| break :blk err };
        const at = declared(s, instance) catch |err| break :blk err;
        break :blk at.orders.append(s.names(), o);
    });
}

/// Slot `add_set`.
fn addSet(self: ?*A.ke_assembly, schedule: ?[*:0]const u8, name: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const set = s.copy(name) catch |err| break :blk err;
        const sets = s.setsOf(s.copy(schedule) catch |err| break :blk err) catch |err| break :blk err;
        break :blk sets.names.append(s.names(), set);
    });
}

/// Slot `order_set`.
fn orderSet(self: ?*A.ke_assembly, schedule: ?[*:0]const u8, first: ?[*:0]const u8, then: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const o = SetOrder{ .first = s.copy(first) catch |err| break :blk err, .then = s.copy(then) catch |err| break :blk err };
        const sets = s.setsOf(s.copy(schedule) catch |err| break :blk err) catch |err| break :blk err;
        break :blk sets.orders.append(s.names(), o);
    });
}

/// Slot `set_default`.
fn setDefault(self: ?*A.ke_assembly, contract: ?[*:0]const u8, instance: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const target = s.copy(instance) catch |err| break :blk err;
        break :blk s.defaults.put(s.names(), s.copy(contract) catch |err| break :blk err, target);
    });
}

/// Collects the reasons a composition cannot be assembled, each handed to the caller's report as found.
const Report = struct {
    callback: A.ke_assembly_report_fn,
    ctx: ?*anyopaque,
    count: usize = 0,

    fn add(r: *Report, failure: A.ke_assembly_failure, instance: ?[]const u8, name: ?[]const u8, comptime fmt: []const u8, args: anytype) void {
        r.count += 1;
        var buf: [512]u8 = undefined;
        const detail: [:0]const u8 = std.fmt.bufPrintZ(&buf, fmt, args) catch "a reason too long to print";
        var instance_buf: [256]u8 = undefined;
        var name_buf: [256]u8 = undefined;
        const i: ?[*:0]const u8 = if (instance) |v| (std.fmt.bufPrintZ(&instance_buf, "{s}", .{v}) catch null) else null;
        const n: ?[*:0]const u8 = if (name) |v| (std.fmt.bufPrintZ(&name_buf, "{s}", .{v}) catch null) else null;
        log.warn("cannot assemble: {s}", .{detail});
        if (r.callback) |cb| cb(r.ctx, failure, i, n, detail.ptr);
    }
};

fn slotsOf(part: *const P.ke_part) []const P.ke_part_slot {
    if (part.slot_count == 0) return &.{};
    return @as([*]const P.ke_part_slot, @ptrCast(part.slots.?))[0..part.slot_count];
}

fn hooksOf(part: *const P.ke_part) []const P.ke_part_hook {
    if (part.hook_count == 0) return &.{};
    return @as([*]const P.ke_part_hook, @ptrCast(part.hooks.?))[0..part.hook_count];
}

fn partSetsOf(part: *const P.ke_part) []const P.ke_part_set {
    if (part.set_count == 0) return &.{};
    return @as([*]const P.ke_part_set, @ptrCast(part.sets.?))[0..part.set_count];
}

fn providing(s: *State, contract: []const u8, except: usize, into: *std.ArrayListUnmanaged(usize)) R.Error!void {
    for (s.instances.items, 0..) |*other, j| {
        if (j == except) continue;
        if (other.provides()) |p| if (std.mem.eql(u8, p, contract)) try into.append(s.names(), j);
    }
}

/// Orders `nodes` so that every pair of `edges` comes first-then; false on a cycle. `edges` index `nodes`.
fn topological(allocator: std.mem.Allocator, count: usize, edges: []const [2]usize, out: []usize) R.Error!bool {
    const incoming = try allocator.alloc(usize, count);
    @memset(incoming, 0);
    for (edges) |e| incoming[e[1]] += 1;
    var written: usize = 0;
    var progress = true;
    const done = try allocator.alloc(bool, count);
    @memset(done, false);
    while (progress) {
        progress = false;
        for (0..count) |n| {
            if (done[n] or incoming[n] != 0) continue;
            done[n] = true;
            out[written] = n;
            written += 1;
            progress = true;
            for (edges) |e| if (e[0] == n) {
                incoming[e[1]] -= 1;
            };
        }
    }
    return written == count;
}

fn indexIn(list: []const usize, value: usize) ?usize {
    for (list, 0..) |v, i| if (v == value) return i;
    return null;
}

fn resolveSlots(s: *State, report: *Report, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    const part = self.part.?;
    const slots = slotsOf(part);
    self.slots = try s.names().alloc([]usize, slots.len);
    for (self.bindings.items) |b| {
        for (slots) |slot| {
            if (std.mem.eql(u8, std.mem.span(slot.name.?), b.slot)) break;
        } else report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, b.slot, "{s} binds {s}, a slot its part {s} does not have", .{ self.name, b.slot, self.part_name.? });
    }
    for (slots, 0..) |slot, k| {
        const slot_name = std.mem.span(slot.name.?);
        const contract = std.mem.span(slot.contract.?);
        var chosen: std.ArrayListUnmanaged(usize) = .empty;
        for (self.bindings.items) |b| {
            if (!std.mem.eql(u8, b.slot, slot_name)) continue;
            const j = s.by_name.get(b.target) orelse {
                report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, slot_name, "{s}.{s} is bound to {s}, which is no instance", .{ self.name, slot_name, b.target });
                continue;
            };
            const p = s.instances.items[j].provides() orelse "nothing";
            if (!std.mem.eql(u8, p, contract)) {
                report.add(A.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT, self.name, slot_name, "{s}.{s} takes {s}, and {s} provides {s}", .{ self.name, slot_name, contract, b.target, p });
                continue;
            }
            try chosen.append(s.names(), j);
        }
        const explicit = chosen.items.len > 0 or anyBinding(self, slot_name);
        if (!explicit) {
            if (s.defaults.get(contract)) |d| {
                if (s.by_name.get(d)) |j| try chosen.append(s.names(), j) else report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, null, contract, "the default of {s} is {s}, which is no instance", .{ contract, d });
            } else try providing(s, contract, at, &chosen);
        }
        const many = slot.cardinality == P.KE_PART_CARDINALITY_MANY;
        if (!many and chosen.items.len > 1) {
            report.add(A.KE_ASSEMBLY_FAILURE_AMBIGUOUS, self.name, slot_name, "{s}.{s} takes one {s} and {d} provide it; bind one or name the default", .{ self.name, slot_name, contract, chosen.items.len });
        } else if (slot.cardinality == P.KE_PART_CARDINALITY_ONE and chosen.items.len == 0 and !explicit) {
            report.add(A.KE_ASSEMBLY_FAILURE_UNSATISFIED, self.name, slot_name, "{s}.{s} takes one {s} and no instance provides it", .{ self.name, slot_name, contract });
        }
        self.slots[k] = try orderSlot(s, report, self, slot_name, chosen.items);
    }
}

fn anyBinding(self: *const Instance, slot: []const u8) bool {
    for (self.bindings.items) |b| if (std.mem.eql(u8, b.slot, slot)) return true;
    return false;
}

fn orderSlot(s: *State, report: *Report, self: *const Instance, slot: []const u8, chosen: []const usize) R.Error![]usize {
    var edges: std.ArrayListUnmanaged([2]usize) = .empty;
    for (self.orders.items) |o| {
        if (!std.mem.eql(u8, o.slot, slot)) continue;
        const a = indexIn(chosen, s.by_name.get(o.first) orelse std.math.maxInt(usize));
        const b = indexIn(chosen, s.by_name.get(o.then) orelse std.math.maxInt(usize));
        if (a == null or b == null) {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, slot, "{s}.{s} orders {s} before {s}, and both must be bound to it", .{ self.name, slot, o.first, o.then });
            continue;
        }
        try edges.append(s.names(), .{ a.?, b.? });
    }
    const sorted = try s.names().alloc(usize, chosen.len);
    if (!try topological(s.names(), chosen.len, edges.items, sorted)) {
        report.add(A.KE_ASSEMBLY_FAILURE_CYCLE, self.name, slot, "the orders of {s}.{s} contradict each other", .{ self.name, slot });
        return try s.names().dupe(usize, chosen);
    }
    for (sorted) |*v| v.* = chosen[v.*];
    return sorted;
}

fn resolveHooks(s: *State, report: *Report, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    const hooks = hooksOf(self.part.?);
    self.hooked = try s.names().alloc(Hooked, hooks.len);
    for (self.hookings.items) |h| {
        for (hooks) |declared_hook| {
            if (std.mem.eql(u8, std.mem.span(declared_hook.name.?), h.hook)) break;
        } else report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, h.hook, "{s} hooks {s}, a hook its part {s} does not have", .{ self.name, h.hook, self.part_name.? });
    }
    for (hooks, 0..) |declared_hook, k| {
        const hook_name = std.mem.span(declared_hook.name.?);
        self.hooked[k] = .{ .schedule = std.math.maxInt(usize), .set = "" };
        const h = for (self.hookings.items) |x| {
            if (std.mem.eql(u8, x.hook, hook_name)) break x;
        } else {
            report.add(A.KE_ASSEMBLY_FAILURE_UNHOOKED, self.name, hook_name, "{s}.{s} is bound to no schedule", .{ self.name, hook_name });
            continue;
        };
        const j = s.by_name.get(h.schedule) orelse {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, hook_name, "{s}.{s} is hooked to {s}, which is no instance", .{ self.name, hook_name, h.schedule });
            continue;
        };
        const p = s.instances.items[j].provides() orelse "nothing";
        if (!std.mem.eql(u8, p, schedule_contract)) {
            report.add(A.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT, self.name, hook_name, "{s}.{s} is hooked to {s}, which provides {s}, not a schedule", .{ self.name, hook_name, h.schedule, p });
            continue;
        }
        self.hooked[k] = .{ .schedule = j, .set = h.set orelse try s.names().dupeZ(u8, std.mem.span(declared_hook.default_set.?)) };
        for (partSetsOf(self.part.?)) |introduced| {
            if (!std.mem.eql(u8, std.mem.span(introduced.hook.?), hook_name)) continue;
            const sets = try s.setsOf(h.schedule);
            const name = try s.names().dupeZ(u8, std.mem.span(introduced.name.?));
            try sets.names.append(s.names(), name);
            if (introduced.after) |after| try sets.orders.append(s.names(), .{ .first = try s.names().dupeZ(u8, std.mem.span(after)), .then = name });
        }
    }
}

fn hasSet(sets: *const Sets, name: []const u8) bool {
    for (sets.names.items) |n| if (std.mem.eql(u8, n, name)) return true;
    return false;
}

fn checkSets(s: *State, report: *Report) R.Error!void {
    var it = s.sets.iterator();
    while (it.next()) |entry| {
        const sets = entry.value_ptr;
        if (s.by_name.get(entry.key_ptr.*) == null) report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, entry.key_ptr.*, null, "sets are introduced in {s}, which is no instance", .{entry.key_ptr.*});
        var edges: std.ArrayListUnmanaged([2]usize) = .empty;
        for (sets.orders.items) |o| {
            const a = setIndex(sets, o.first);
            const b = setIndex(sets, o.then);
            if (a == null or b == null) {
                report.add(A.KE_ASSEMBLY_FAILURE_UNHOOKED, entry.key_ptr.*, if (a == null) o.first else o.then, "{s} orders {s} before {s}, and both must be sets of it", .{ entry.key_ptr.*, o.first, o.then });
                continue;
            }
            try edges.append(s.names(), .{ a.?, b.? });
        }
        const sorted = try s.names().alloc(usize, sets.names.items.len);
        if (!try topological(s.names(), sets.names.items.len, edges.items, sorted)) {
            report.add(A.KE_ASSEMBLY_FAILURE_CYCLE, entry.key_ptr.*, null, "the orders of the sets of {s} contradict each other", .{entry.key_ptr.*});
            continue;
        }
        var ordered = try s.names().alloc(Name, sorted.len);
        for (sorted, 0..) |v, i| ordered[i] = sets.names.items[v];
        sets.names = .fromOwnedSlice(ordered);
    }
    for (s.instances.items) |*self| {
        for (self.hooked, 0..) |h, k| {
            if (h.schedule == std.math.maxInt(usize)) continue;
            const schedule = s.instances.items[h.schedule].name;
            const known = if (s.sets.getPtr(schedule)) |sets| hasSet(sets, h.set) else false;
            if (!known) report.add(A.KE_ASSEMBLY_FAILURE_UNHOOKED, self.name, std.mem.span(hooksOf(self.part.?)[k].name.?), "{s} joins the set {s} of {s}, which it does not have", .{ self.name, h.set, schedule });
        }
    }
}

fn setIndex(sets: *const Sets, name: []const u8) ?usize {
    for (sets.names.items, 0..) |n, i| if (std.mem.eql(u8, n, name)) return i;
    return null;
}

fn plan(s: *State, report: *Report) R.Error!void {
    var edges: std.ArrayListUnmanaged([2]usize) = .empty;
    for (s.instances.items, 0..) |*self, at| {
        for (self.slots) |targets| for (targets) |t| try edges.append(s.names(), .{ t, at });
        for (self.hooked) |h| if (h.schedule != std.math.maxInt(usize)) try edges.append(s.names(), .{ h.schedule, at });
    }
    const sorted = try s.names().alloc(usize, s.instances.items.len);
    if (!try topological(s.names(), s.instances.items.len, edges.items, sorted)) {
        report.add(A.KE_ASSEMBLY_FAILURE_CYCLE, null, null, "the instances need each other", .{});
        return;
    }
    s.plan = sorted;
}

fn setLogs(s: *State) void {
    if (s.log_callback == null) return;
    var seen: std.ArrayListUnmanaged(*const anyopaque) = .empty;
    var it = s.parts.valueIterator();
    while (it.next()) |part| {
        const setter = part.*.set_log orelse continue;
        const key: *const anyopaque = @ptrCast(setter);
        if (std.mem.indexOfScalar(*const anyopaque, seen.items, key) != null) continue;
        seen.append(s.names(), key) catch return;
        setter(s.log_callback, s.log_ctx);
    }
}

/// Slot `resolve`. Every reason is reported before it returns, and nothing is created.
fn resolve(self: ?*A.ke_assembly, callback: A.ke_assembly_report_fn, ctx: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        var report = Report{ .callback = callback, .ctx = ctx };
        break :blk resolveAll(s, &report);
    });
}

fn resolveAll(s: *State, report: *Report) R.Error!void {
    for (s.instances.items) |*self| {
        if (self.external != null) continue;
        const part_name = self.part_name orelse {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, null, "{s} is bound, hooked or ordered but never declared", .{self.name});
            continue;
        };
        self.part = s.parts.get(part_name) orelse blk: {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_PART, self.name, part_name, "{s} is an instance of {s}, which no one added", .{ self.name, part_name });
            break :blk null;
        };
    }
    for (s.instances.items, 0..) |*self, at| {
        if (self.part == null) continue;
        try resolveSlots(s, report, at);
        try resolveHooks(s, report, at);
    }
    var defaults = s.defaults.iterator();
    while (defaults.next()) |d| if (s.by_name.get(d.value_ptr.*) == null)
        report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, null, d.key_ptr.*, "the default of {s} is {s}, which is no instance", .{ d.key_ptr.*, d.value_ptr.* });
    try checkSets(s, report);
    if (report.count == 0) try plan(s, report);
    if (report.count > 0) return error.Unresolved;
    setLogs(s);
    s.resolved = true;
}

fn registerSets(s: *State, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    const sets = s.sets.getPtr(self.name) orelse return;
    const schedule: *abi_schedule.c.ke_schedule = @ptrCast(@alignCast(refOf(self)));
    for (sets.names.items) |name| {
        var after: std.ArrayListUnmanaged(abi_schedule.c.ke_schedule_set_id) = .empty;
        for (sets.orders.items) |o| if (std.mem.eql(u8, o.then, name)) try after.append(s.names(), sets.ids.get(o.first).?);
        var id: abi_schedule.c.ke_schedule_set_id = 0;
        try R.check(schedule.register_set.?(schedule, &.{ .name = name.ptr, .after = if (after.items.len > 0) after.items.ptr else null, .after_count = @intCast(after.items.len) }, &id));
        try sets.ids.put(s.names(), name, id);
    }
}

fn refOf(self: *const Instance) ?*anyopaque {
    if (self.external) |e| return e;
    return if (self.made) |m| m.ref else null;
}

fn make(s: *State, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    const part = self.part.?;
    const bound = try s.names().alloc(P.ke_part_bound, self.slots.len);
    for (self.slots, 0..) |targets, k| {
        const refs = try s.names().alloc(?*anyopaque, targets.len);
        for (targets, 0..) |t, i| refs[i] = refOf(&s.instances.items[t]);
        bound[k] = .{ .instances = if (refs.len > 0) @ptrCast(refs.ptr) else null, .count = refs.len };
    }
    const hooked = try s.names().alloc(P.ke_part_hooked, self.hooked.len);
    for (self.hooked, 0..) |h, k| {
        const schedule = &s.instances.items[h.schedule];
        hooked[k] = .{ .schedule = @ptrCast(@alignCast(refOf(schedule))), .set = s.sets.getPtr(schedule.name).?.ids.get(h.set).? };
    }
    var settings: ?*abi_settings.c.ke_settings = null;
    try R.check(s.configuration.section.?(s.configuration, self.section.?.ptr, &settings));
    var made: P.ke_part_instance = undefined;
    R.check(part.create.?(part, if (bound.len > 0) &bound[0] else null, if (hooked.len > 0) &hooked[0] else null, settings, &made)) catch |err| {
        log.warn("creating {s}, an instance of {s}, failed: {t}", .{ self.name, self.part_name.?, err });
        return err;
    };
    self.made = made;
    try registerSets(s, at);
    if (part.ready) |ready| {
        var completion: ?*abi_completion.c.ke_completion = null;
        try R.check(ready(made.ref, &completion));
        s.waiting = completion;
    }
}

fn pumpAll(s: *State) void {
    for (s.plan[0..s.next]) |at| {
        const self = &s.instances.items[at];
        const part = self.part orelse continue;
        if (part.pump) |pump| pump(self.made.?.ref);
    }
}

fn destroyMade(s: *State) void {
    if (s.waiting) |w| {
        w.release.?(w);
        s.waiting = null;
    }
    var i = s.plan.len;
    while (i > 0) {
        i -= 1;
        const self = &s.instances.items[s.plan[i]];
        const made = self.made orelse continue;
        if (made.destroy) |d| d(made.ref);
        self.made = null;
    }
}

/// Slot `advance`.
fn advance(self: ?*A.ke_assembly) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (!s.resolved) return R.code(error.NotSupported);
    advanceAll(s) catch |err| {
        if (err != error.Pending) destroyMade(s);
        return R.code(err);
    };
    return R.ok;
}

fn advanceAll(s: *State) R.Error!void {
    if (s.waiting) |w| {
        var result: abi_result.c.ke_result = R.ok;
        if (!w.poll.?(w, &result)) {
            pumpAll(s);
            return error.Pending;
        }
        w.release.?(w);
        s.waiting = null;
        try R.check(result);
    }
    while (s.next < s.plan.len) {
        const at = s.plan[s.next];
        s.next += 1;
        if (s.instances.items[at].external != null) {
            try registerSets(s, at);
            continue;
        }
        try make(s, at);
        if (s.waiting != null) {
            pumpAll(s);
            return error.Pending;
        }
    }
}

/// Slot `get`.
fn get(self: ?*A.ke_assembly, name: ?[*:0]const u8, out_instance: ?*?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const out = out_instance orelse return R.code(error.InvalidArgument);
    const instance = s.instanceOf(std.mem.span(name orelse return R.code(error.InvalidArgument))) orelse return R.code(error.NotFound);
    out.* = refOf(instance) orelse return R.code(error.NotFound);
    return R.ok;
}

fn destroy(self: ?*A.ke_assembly) callconv(.c) void {
    const s = stateOf(self) orelse return;
    destroyMade(s);
    s.arena.deinit();
    gpa.destroy(s);
}

/// The factory declared in assembly_default_create.h.
export fn ke_assembly_default_create(configuration: ?*abi_configuration.c.ke_configuration, out_assembly: ?*A.ke_assembly_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_assembly orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(A.ke_assembly_handle);
    const cfg = configuration orelse return R.code(error.InvalidArgument);
    const s = gpa.create(State) catch |err| return R.code(err);
    s.* = .{
        .api = .{ .handle = null, .route_log = routeLog, .add_part = addPart, .add_instance = addInstance, .add_external = addExternal, .bind = bind, .hook = hook, .order = order, .add_set = addSet, .order_set = orderSet, .set_default = setDefault, .resolve = resolve, .advance = advance, .get = get },
        .configuration = cfg,
        .arena = std.heap.ArenaAllocator.init(gpa),
    };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const Probe = struct {
    var created: [8][]const u8 = undefined;
    var created_count: usize = 0;
    var destroyed: [8][]const u8 = undefined;
    var destroyed_count: usize = 0;
    var fail_on: ?[]const u8 = null;
    var seen_slots: [4]?*anyopaque = .{ null, null, null, null };
    var seen_count: usize = 0;
    var seen_hook: P.ke_part_hooked = undefined;
    var pumps: usize = 0;
    var logs_set: usize = 0;
    var ready_done = true;

    fn reset() void {
        created_count = 0;
        destroyed_count = 0;
        fail_on = null;
        seen_count = 0;
        pumps = 0;
        logs_set = 0;
        ready_done = true;
    }
};

const Thing = struct { name: []const u8, first: ?*anyopaque = null };
var things: [8]Thing = undefined;

fn thingCreate(self: ?*const P.ke_part, bound: ?*const P.ke_part_bound, hooked: ?*const P.ke_part_hooked, _: ?*abi_settings.c.ke_settings, out: ?*P.ke_part_instance) callconv(.c) abi_result.c.ke_result {
    const part = self.?;
    const name = std.mem.span(part.name.?);
    if (Probe.fail_on) |f| if (std.mem.eql(u8, f, name)) return R.code(error.Io);
    if (bound) |b| {
        const first: *const P.ke_part_bound = b;
        Probe.seen_count = first.count;
        if (first.count > 0) for (@as([*]const ?*anyopaque, @ptrCast(first.instances))[0..first.count], 0..) |r, i| {
            Probe.seen_slots[i] = r;
        };
    }
    if (hooked) |h| Probe.seen_hook = h.*;
    const at = Probe.created_count;
    Probe.created[at] = name;
    Probe.created_count += 1;
    things[at] = .{ .name = name, .first = if (bound) |b| (if (b.count > 0) @as([*]const ?*anyopaque, @ptrCast(b.instances))[0] else null) else null };
    out.?.* = .{ .ref = &things[at], .destroy = thingDestroy };
    return R.ok;
}

fn thingDestroy(ref: ?*anyopaque) callconv(.c) void {
    const t: *Thing = @ptrCast(@alignCast(ref.?));
    Probe.destroyed[Probe.destroyed_count] = t.name;
    Probe.destroyed_count += 1;
}

fn countLog(_: P.ke_log_callback, _: ?*anyopaque) callconv(.c) void {
    Probe.logs_set += 1;
}

var probe_completion: abi_completion.c.ke_completion = .{ .poll = pollProbe, .release = releaseProbe };

fn pollProbe(_: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
    out.?.* = R.ok;
    return Probe.ready_done;
}

fn releaseProbe(_: ?*abi_completion.c.ke_completion) callconv(.c) void {}

fn readyProbe(_: ?*anyopaque, out: ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    out.?.* = &probe_completion;
    return R.ok;
}

fn pumpProbe(_: ?*anyopaque) callconv(.c) void {
    Probe.pumps += 1;
}

const one_gear = [_]P.ke_part_slot{.{ .name = "gear", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_ONE }};
const many_gears = [_]P.ke_part_slot{.{ .name = "gears", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_MANY }};
const tick_hook = [_]P.ke_part_hook{.{ .name = "tick", .default_set = "update" }};

const gear_a = P.ke_part{ .name = "gear_a", .provides = "ke_gear", .create = thingCreate, .set_log = countLog };
const gear_b = P.ke_part{ .name = "gear_b", .provides = "ke_gear", .create = thingCreate, .set_log = countLog };
const gear_slow = P.ke_part{ .name = "gear_slow", .provides = "ke_gear", .create = thingCreate, .ready = readyProbe, .pump = pumpProbe };
const wheel = P.ke_part{ .name = "wheel", .provides = "ke_wheel", .slots = &one_gear[0], .slot_count = 1, .create = thingCreate };
const axle = P.ke_part{ .name = "axle", .provides = "ke_axle", .slots = &many_gears[0], .slot_count = 1, .create = thingCreate };
const ticker = P.ke_part{ .name = "ticker", .hooks = &tick_hook[0], .hook_count = 1, .create = thingCreate };
const loop_wheel = P.ke_part{ .name = "loop_wheel", .provides = "ke_gear", .slots = &one_gear[0], .slot_count = 1, .create = thingCreate };

const Rig = struct {
    cfg: zsub.For(abi_configuration.c.ke_configuration),
    settings: abi_settings.c.ke_settings,
    handle: A.ke_assembly_handle,
    failures: [16]A.ke_assembly_failure = undefined,
    failure_count: usize = 0,

    fn init(rig: *Rig) !void {
        Probe.reset();
        rig.failure_count = 0;
        rig.settings = std.mem.zeroes(abi_settings.c.ke_settings);
        try rig.cfg.init();
        _ = rig.cfg.when(.section).does(sectionOf);
        try R.check(ke_assembly_default_create(rig.cfg.api(), &rig.handle));
        rig_settings = &rig.settings;
    }

    fn a(rig: *Rig) *A.ke_assembly {
        return rig.handle.ref.?;
    }

    fn part(rig: *Rig, p: *const P.ke_part) !void {
        try R.check(rig.a().add_part.?(rig.a(), p));
    }

    fn instance(rig: *Rig, name: [*:0]const u8, p: [*:0]const u8) !void {
        try R.check(rig.a().add_instance.?(rig.a(), name, p, name));
    }

    fn resolve(rig: *Rig) abi_result.c.ke_result {
        return rig.a().resolve.?(rig.a(), record, rig);
    }

    fn ref(rig: *Rig, name: [*:0]const u8) !?*anyopaque {
        var out: ?*anyopaque = null;
        try R.check(rig.a().get.?(rig.a(), name, &out));
        return out;
    }

    fn thing(rig: *Rig, name: [*:0]const u8) !*Thing {
        return @ptrCast(@alignCast((try rig.ref(name)).?));
    }

    fn deinit(rig: *Rig) void {
        rig.handle.destroy.?(rig.handle.ref);
        rig.cfg.deinit();
    }

    fn record(ctx: ?*anyopaque, failure: A.ke_assembly_failure, _: ?[*:0]const u8, _: ?[*:0]const u8, _: ?[*:0]const u8) callconv(.c) void {
        const rig: *Rig = @ptrCast(@alignCast(ctx.?));
        rig.failures[rig.failure_count] = failure;
        rig.failure_count += 1;
    }

    fn reported(rig: *const Rig, failure: A.ke_assembly_failure) bool {
        return std.mem.indexOfScalar(A.ke_assembly_failure, rig.failures[0..rig.failure_count], failure) != null;
    }
};

var rig_settings: *abi_settings.c.ke_settings = undefined;

fn sectionOf(args: zsub.For(abi_configuration.c.ke_configuration).Args(.section)) abi_result.c.ke_result {
    args[2].?.* = rig_settings;
    return R.ok;
}

fn createdIs(expected: []const []const u8) !void {
    try testing.expectEqual(expected.len, Probe.created_count);
    for (expected, 0..) |e, i| try testing.expectEqualStrings(e, Probe.created[i]);
}

test "an instance is created after the only instance providing its slot's contract, which it receives" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&wheel);
    try rig.part(&gear_a);
    try rig.instance("front", "wheel");
    try rig.instance("cog", "gear_a");
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try createdIs(&.{ "gear_a", "wheel" });
    var cog: ?*anyopaque = null;
    try R.check(rig.a().get.?(rig.a(), "cog", &cog));
    try testing.expectEqual(cog, Probe.seen_slots[0]);
}

test "a slot takes what the composition binds, else the contract's default, else the only candidate" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&wheel);
    try rig.part(&gear_a);
    try rig.part(&gear_b);
    try rig.instance("front", "wheel");
    try rig.instance("rear", "wheel");
    try rig.instance("a", "gear_a");
    try rig.instance("b", "gear_b");
    try R.check(rig.a().bind.?(rig.a(), "front", "gear", "b"));
    try R.check(rig.a().set_default.?(rig.a(), "ke_gear", "a"));
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try testing.expectEqual(try rig.ref("b"), (try rig.thing("front")).first);
    try testing.expectEqual(try rig.ref("a"), (try rig.thing("rear")).first);
}

test "every reason a composition cannot be assembled is reported together, and nothing is created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&wheel);
    try rig.part(&gear_a);
    try rig.part(&gear_b);
    try rig.part(&ticker);
    try rig.instance("lonely", "wheel");
    try rig.instance("a", "gear_a");
    try rig.instance("b", "gear_b");
    try rig.instance("ghost", "no_such_part");
    try rig.instance("idle", "ticker");
    try R.check(rig.a().bind.?(rig.a(), "a", "gear", "b"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_AMBIGUOUS));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNKNOWN_PART));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNHOOKED));
    try testing.expectEqual(R.code(error.NotSupported), rig.a().advance.?(rig.a()));
    try testing.expectEqual(@as(usize, 0), Probe.created_count);
}

test "a slot no instance provides is unsatisfied, and one bound to another contract is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&wheel);
    try rig.part(&axle);
    try rig.instance("front", "wheel");
    try rig.instance("rear", "wheel");
    try rig.instance("shaft", "axle");
    try R.check(rig.a().bind.?(rig.a(), "rear", "gear", "shaft"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNSATISFIED));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT));
}

test "instances that need each other are a cycle" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&loop_wheel);
    try rig.instance("x", "loop_wheel");
    try rig.instance("y", "loop_wheel");
    try R.check(rig.a().bind.?(rig.a(), "x", "gear", "y"));
    try R.check(rig.a().bind.?(rig.a(), "y", "gear", "x"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_CYCLE));
}

test "a slot that takes many receives its instances in the order the composition gave, and contradicting orders are a cycle" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&axle);
    try rig.part(&gear_a);
    try rig.instance("shaft", "axle");
    try rig.instance("first", "gear_a");
    try rig.instance("second", "gear_a");
    try R.check(rig.a().bind.?(rig.a(), "shaft", "gears", "first"));
    try R.check(rig.a().bind.?(rig.a(), "shaft", "gears", "second"));
    try R.check(rig.a().order.?(rig.a(), "shaft", "gears", "second", "first"));
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    var second: ?*anyopaque = null;
    try R.check(rig.a().get.?(rig.a(), "second", &second));
    try testing.expectEqual(@as(usize, 2), Probe.seen_count);
    try testing.expectEqual(second, Probe.seen_slots[0]);

    var other: Rig = undefined;
    try other.init();
    defer other.deinit();
    try other.part(&axle);
    try other.part(&gear_a);
    try other.instance("shaft", "axle");
    try other.instance("first", "gear_a");
    try other.instance("second", "gear_a");
    try R.check(other.a().bind.?(other.a(), "shaft", "gears", "first"));
    try R.check(other.a().bind.?(other.a(), "shaft", "gears", "second"));
    try R.check(other.a().order.?(other.a(), "shaft", "gears", "second", "first"));
    try R.check(other.a().order.?(other.a(), "shaft", "gears", "first", "second"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, other.resolve());
    try testing.expect(other.reported(A.KE_ASSEMBLY_FAILURE_CYCLE));
}

var schedule_sub: zsub.For(abi_schedule.c.ke_schedule) = undefined;

fn scheduleCreate(_: ?*const P.ke_part, _: ?*const P.ke_part_bound, _: ?*const P.ke_part_hooked, _: ?*abi_settings.c.ke_settings, out: ?*P.ke_part_instance) callconv(.c) abi_result.c.ke_result {
    out.?.* = .{ .ref = schedule_sub.api(), .destroy = null };
    return R.ok;
}

const fake_schedule = P.ke_part{ .name = "fake_schedule", .provides = "ke_schedule", .create = scheduleCreate };

test "a hook receives its schedule and the id of the set it joins, registered in the order the composition gave" {
    try schedule_sub.init();
    defer schedule_sub.deinit();
    _ = schedule_sub.when(.register_set).writesFresh(2);
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&fake_schedule);
    try rig.part(&ticker);
    try rig.instance("frame", "fake_schedule");
    try rig.instance("clock", "ticker");
    try R.check(rig.a().add_set.?(rig.a(), "frame", "post_update"));
    try R.check(rig.a().add_set.?(rig.a(), "frame", "update"));
    try R.check(rig.a().order_set.?(rig.a(), "frame", "update", "post_update"));
    try R.check(rig.a().hook.?(rig.a(), "clock", "tick", "frame", null));
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try schedule_sub.received(.register_set).times(2);
    try testing.expectEqual(@as(?*abi_schedule.c.ke_schedule, schedule_sub.api()), Probe.seen_hook.schedule);
    try testing.expect(Probe.seen_hook.set != 0);
}

test "an instance that becomes usable later holds back the rest, pumping the instances made, until its completion finishes" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gear_slow);
    try rig.part(&wheel);
    try rig.instance("slow", "gear_slow");
    try rig.instance("front", "wheel");
    try R.check(rig.resolve());
    Probe.ready_done = false;
    try testing.expectEqual(R.code(error.Pending), rig.a().advance.?(rig.a()));
    try testing.expectEqual(R.code(error.Pending), rig.a().advance.?(rig.a()));
    try createdIs(&.{"gear_slow"});
    try testing.expect(Probe.pumps >= 2);
    Probe.ready_done = true;
    try R.check(rig.a().advance.?(rig.a()));
    try createdIs(&.{ "gear_slow", "wheel" });
}

test "an instance that fails to be created destroys every one made before it, in reverse" {
    var made: Rig = undefined;
    try made.init();
    defer made.deinit();
    try made.part(&gear_a);
    try made.part(&wheel);
    try made.part(&axle);
    try made.instance("cog", "gear_a");
    try made.instance("front", "wheel");
    try made.instance("shaft", "axle");
    try R.check(made.a().bind.?(made.a(), "shaft", "gears", "cog"));
    try R.check(made.resolve());
    Probe.fail_on = "axle";
    try testing.expectEqual(R.code(error.Io), made.a().advance.?(made.a()));
    try testing.expectEqual(Probe.created_count, Probe.destroyed_count);
    try testing.expectEqualStrings(Probe.created[0], Probe.destroyed[Probe.destroyed_count - 1]);
}

test "an external instance is handed to the slots that take it and never destroyed" {
    var rig: Rig = undefined;
    try rig.init();
    try rig.part(&wheel);
    var outside = Thing{ .name = "outside" };
    try R.check(rig.a().add_external.?(rig.a(), "given", "ke_gear", &outside));
    try rig.instance("front", "wheel");
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try testing.expectEqual(@as(?*anyopaque, &outside), Probe.seen_slots[0]);
    rig.deinit();
    try testing.expectEqual(@as(usize, 1), Probe.destroyed_count);
    try testing.expectEqualStrings("wheel", Probe.destroyed[0]);
}

fn discardLine(_: ?*anyopaque, _: abi_logger.c.ke_log_level, _: ?[*:0]const u8, _: ?[*:0]const u8) callconv(.c) void {}

test "each distinct log setter of the parts is called once, before anything is created, once the log is routed" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try testing.expectEqual(R.code(error.InvalidArgument), rig.a().route_log.?(rig.a(), null, null));
    try R.check(rig.a().route_log.?(rig.a(), discardLine, null));
    try rig.part(&gear_a);
    try rig.part(&gear_b);
    try rig.instance("a", "gear_a");
    try R.check(rig.resolve());
    try testing.expectEqual(@as(usize, 1), Probe.logs_set);
    try testing.expectEqual(@as(usize, 0), Probe.created_count);
}

test "a name taken twice is refused, and nothing is gathered after resolve" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gear_a);
    try testing.expectEqual(R.code(error.AlreadyExists), rig.a().add_part.?(rig.a(), &gear_a));
    try rig.instance("a", "gear_a");
    try testing.expectEqual(R.code(error.AlreadyExists), rig.a().add_instance.?(rig.a(), "a", "gear_a", "a"));
    try R.check(rig.resolve());
    try testing.expectEqual(R.code(error.NotSupported), rig.a().add_instance.?(rig.a(), "b", "gear_a", "b"));
    try testing.expectEqual(R.code(error.NotSupported), rig.resolve());
}

test "assembling and destroying leaves no block allocated" {
    var rig: Rig = undefined;
    try rig.init();
    try rig.part(&wheel);
    try rig.part(&gear_a);
    try rig.instance("front", "wheel");
    try rig.instance("cog", "gear_a");
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    rig.deinit();
    try heap.expectNoLeaks();
}
