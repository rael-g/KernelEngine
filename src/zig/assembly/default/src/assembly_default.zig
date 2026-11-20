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
const abi_settings = @import("abi_settings");
const heap = @import("heap");

const R = @import("result").Result(.{.{ error.Unresolved, abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED }});
const log = std.log.scoped(.assembly_default);
const gpa = heap.gpa;

const P = abi_part.c;
const A = abi_assembly.c;
const Name = [:0]const u8;

const Binding = struct { slot: Name, target: Name };
const Order = struct { slot: ?Name, first: Name, then: Name };
const External = struct { contract: Name, ref: *anyopaque };
const Problem = struct { failure: A.ke_assembly_failure, instance: ?Name, name: ?Name, detail: Name };

/// One instance of the composition: of a part, or made outside as one vtable per contract. After resolve, `slots`
/// holds the instances each slot takes; `made` is set once created, and an
/// external one never is.
const Instance = struct {
    name: Name,
    part_name: ?Name = null,
    section: ?Name = null,
    externals: std.ArrayListUnmanaged(External) = .empty,
    part: ?*const P.ke_part = null,
    bindings: std.ArrayListUnmanaged(Binding) = .empty,
    orders: std.ArrayListUnmanaged(Order) = .empty,
    slots: [][]usize = &.{},
    positions: [][]usize = &.{},
    made: ?P.ke_owner = null,

    fn isExternal(self: *const Instance) bool {
        return self.externals.items.len > 0;
    }

    fn contractIndex(self: *const Instance, contract: []const u8) ?usize {
        if (self.isExternal()) {
            for (self.externals.items, 0..) |e, i| if (std.mem.eql(u8, e.contract, contract)) return i;
            return null;
        }
        const part = self.part orelse return null;
        for (providesOf(part), 0..) |c, i| if (std.mem.eql(u8, std.mem.span(c.?), contract)) return i;
        return null;
    }

    fn provides(self: *const Instance, contract: []const u8) bool {
        return self.contractIndex(contract) != null;
    }

    /// The vtable of `contract`: the external given for it, or what the part says of its instance once made.
    fn refFor(self: *const Instance, contract: []const u8) ?*anyopaque {
        const i = self.contractIndex(contract) orelse return null;
        if (self.isExternal()) return self.externals.items[i].ref;
        const made = self.made orelse return null;
        return if (self.part.?.provided) |provided| provided(made.ref, i) else made.ref;
    }
};

fn providesOf(part: *const P.ke_part) []const ?[*:0]const u8 {
    if (part.provides_count == 0) return &.{};
    return @as([*]const ?[*:0]const u8, @ptrCast(part.provides.?))[0..part.provides_count];
}

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
    problems: std.ArrayListUnmanaged(Problem) = .empty,
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

    /// Remembers a mistake gathering found, for resolve to report with the others.
    fn problem(s: *State, failure: A.ke_assembly_failure, instance: ?Name, name: ?Name, comptime fmt: []const u8, args: anytype) R.Error!void {
        try s.problems.append(s.names(), .{ .failure = failure, .instance = instance, .name = name, .detail = try std.fmt.allocPrintSentinel(s.names(), fmt, args, 0) });
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
        if (entry.found_existing) break :blk s.problem(A.KE_ASSEMBLY_FAILURE_DUPLICATE, null, s.copy(part.name) catch |err| break :blk err, "two parts are named {s}", .{name});
        entry.value_ptr.* = part;
    });
}

/// The instance named `name`, declared now when nothing named it yet; one only bound or ordered so far has
/// no part and no external.
fn declared(s: *State, name: ?[*:0]const u8) R.Error!*Instance {
    const n = std.mem.span(name orelse return error.InvalidArgument);
    if (s.instanceOf(n)) |found| return found;
    const copied = try s.copy(name);
    try s.by_name.put(s.names(), copied, s.instances.items.len);
    try s.instances.append(s.names(), .{ .name = copied });
    return s.instanceOf(n).?;
}

fn isPlaceholder(self: *const Instance) bool {
    return self.part_name == null and !self.isExternal();
}

/// Slot `add_instance`.
fn addInstance(self: ?*A.ke_assembly, name: ?[*:0]const u8, part: ?[*:0]const u8, section: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const part_name = s.copy(part) catch |err| break :blk err;
        const at = declared(s, name) catch |err| break :blk err;
        if (!isPlaceholder(at)) break :blk s.problem(A.KE_ASSEMBLY_FAILURE_DUPLICATE, at.name, null, "two instances are named {s}", .{at.name});
        at.part_name = part_name;
        at.section = if (section != null) s.copy(section) catch |err| break :blk err else null;
    });
}

/// Slot `add_external`.
fn addExternal(self: ?*A.ke_assembly, name: ?[*:0]const u8, contract: ?[*:0]const u8, instance: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const ref = instance orelse break :blk error.InvalidArgument;
        const given = s.copy(contract) catch |err| break :blk err;
        const at = declared(s, name) catch |err| break :blk err;
        if (at.part_name != null) break :blk s.problem(A.KE_ASSEMBLY_FAILURE_DUPLICATE, at.name, given, "{s} is an instance of {s} and is also given from outside", .{ at.name, at.part_name.? });
        if (at.provides(given)) break :blk s.problem(A.KE_ASSEMBLY_FAILURE_DUPLICATE, at.name, given, "{s} is given twice as {s}", .{ at.name, given });
        break :blk at.externals.append(s.names(), .{ .contract = given, .ref = ref });
    });
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

/// Slot `order`.
fn order(self: ?*A.ke_assembly, instance: ?[*:0]const u8, slot: ?[*:0]const u8, first: ?[*:0]const u8, then: ?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return code(blk: {
        const s = gathering(self) catch |err| break :blk err;
        const o = Order{ .slot = if (slot != null) s.copy(slot) catch |err| break :blk err else null, .first = s.copy(first) catch |err| break :blk err, .then = s.copy(then) catch |err| break :blk err };
        const at = declared(s, instance) catch |err| break :blk err;
        break :blk at.orders.append(s.names(), o);
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

fn providing(s: *State, contract: []const u8, except: usize, into: *std.ArrayListUnmanaged(usize)) R.Error!void {
    for (s.instances.items, 0..) |*other, j| {
        if (j == except) continue;
        if (other.provides(contract)) try into.append(s.names(), j);
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
        } else report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, b.slot, "{s} binds {s}, a slot its part {s} does not have; it has {s}", .{ self.name, b.slot, self.part_name.?, try slotNames(s, slots) });
    }
    for (slots, 0..) |slot, k| {
        const slot_name = std.mem.span(slot.name.?);
        const contract = std.mem.span(slot.contract.?);
        var chosen: std.ArrayListUnmanaged(usize) = .empty;
        for (self.bindings.items) |b| {
            if (!std.mem.eql(u8, b.slot, slot_name)) continue;
            const j = s.by_name.get(b.target) orelse {
                report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, slot_name, "{s}.{s} is bound to {s}, which is no instance; {s} is provided by {s}", .{ self.name, slot_name, b.target, contract, try providerNames(s, contract, at) });
                continue;
            };
            if (!s.instances.items[j].provides(contract)) {
                report.add(A.KE_ASSEMBLY_FAILURE_WRONG_CONTRACT, self.name, slot_name, "{s}.{s} takes {s}, which {s} does not provide", .{ self.name, slot_name, contract, b.target });
                continue;
            }
            try chosen.append(s.names(), j);
        }
        const many = slot.cardinality == P.KE_PART_CARDINALITY_MANY;
        const explicit = chosen.items.len > 0 or anyBinding(self, slot_name);
        if (!explicit and !many) {
            if (s.defaults.get(contract)) |d| {
                if (s.by_name.get(d)) |j| try chosen.append(s.names(), j) else report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, null, contract, "the default of {s} is {s}, which is no instance", .{ contract, d });
            } else try providing(s, contract, at, &chosen);
        }
        if (!many and chosen.items.len > 1) {
            report.add(A.KE_ASSEMBLY_FAILURE_AMBIGUOUS, self.name, slot_name, "{s}.{s} takes one {s} and {s} provide it; bind one or name the default", .{ self.name, slot_name, contract, try instanceNames(s, chosen.items) });
        } else if (slot.cardinality == P.KE_PART_CARDINALITY_ONE and chosen.items.len == 0 and !explicit) {
            report.add(A.KE_ASSEMBLY_FAILURE_UNSATISFIED, self.name, slot_name, "{s}.{s} takes one {s} and no instance provides it", .{ self.name, slot_name, contract });
        }
        self.slots[k] = try orderSlot(s, report, self, slot_name, chosen.items);
    }
    try positionSlots(s, report, at);
}

/// The position of every instance bound to a slot of the instance at `at`, among all of them: each slot's in its
/// own order, and those the composition ordered across slots in that order.
fn positionSlots(s: *State, report: *Report, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    var offsets = try s.names().alloc(usize, self.slots.len + 1);
    offsets[0] = 0;
    for (self.slots, 0..) |targets, k| offsets[k + 1] = offsets[k] + targets.len;
    const total = offsets[self.slots.len];
    var edges: std.ArrayListUnmanaged([2]usize) = .empty;
    for (self.slots, 0..) |targets, k| {
        if (targets.len > 1) for (1..targets.len) |i| try edges.append(s.names(), .{ offsets[k] + i - 1, offsets[k] + i });
    }
    for (self.orders.items) |o| {
        if (o.slot != null) continue;
        const a = s.by_name.get(o.first);
        const b = s.by_name.get(o.then);
        var firsts: std.ArrayListUnmanaged(usize) = .empty;
        var thens: std.ArrayListUnmanaged(usize) = .empty;
        for (self.slots, 0..) |targets, k| for (targets, 0..) |t, i| {
            if (a != null and t == a.?) try firsts.append(s.names(), offsets[k] + i);
            if (b != null and t == b.?) try thens.append(s.names(), offsets[k] + i);
        };
        if (firsts.items.len == 0 or thens.items.len == 0) {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, null, "{s} orders {s} before {s}, and both must be bound to its slots", .{ self.name, o.first, o.then });
            continue;
        }
        for (firsts.items) |f| for (thens.items) |t| try edges.append(s.names(), .{ f, t });
    }
    const sorted = try s.names().alloc(usize, total);
    if (!try topological(s.names(), total, edges.items, sorted)) {
        report.add(A.KE_ASSEMBLY_FAILURE_CYCLE, self.name, null, "the orders across the slots of {s} contradict each other", .{self.name});
        return;
    }
    const position = try s.names().alloc(usize, total);
    for (sorted, 0..) |node, p| position[node] = p;
    self.positions = try s.names().alloc([]usize, self.slots.len);
    for (self.slots, 0..) |targets, k| self.positions[k] = position[offsets[k] .. offsets[k] + targets.len];
}

fn slotNames(s: *State, slots: []const P.ke_part_slot) R.Error![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (slots, 0..) |slot, i| {
        if (i > 0) try out.appendSlice(s.names(), ", ");
        try out.appendSlice(s.names(), std.mem.span(slot.name.?));
    }
    return if (out.items.len > 0) out.items else "none";
}

fn instanceNames(s: *State, at: []const usize) R.Error![]const u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    for (at, 0..) |j, i| {
        if (i > 0) try out.appendSlice(s.names(), ", ");
        try out.appendSlice(s.names(), s.instances.items[j].name);
    }
    return if (out.items.len > 0) out.items else "no instance";
}

fn providerNames(s: *State, contract: []const u8, except: usize) R.Error![]const u8 {
    var found: std.ArrayListUnmanaged(usize) = .empty;
    try providing(s, contract, except, &found);
    return instanceNames(s, found.items);
}

fn anyBinding(self: *const Instance, slot: []const u8) bool {
    for (self.bindings.items) |b| if (std.mem.eql(u8, b.slot, slot)) return true;
    return false;
}

fn orderSlot(s: *State, report: *Report, self: *const Instance, slot: []const u8, chosen: []const usize) R.Error![]usize {
    var edges: std.ArrayListUnmanaged([2]usize) = .empty;
    for (self.orders.items) |o| {
        const of = o.slot orelse continue;
        if (!std.mem.eql(u8, of, slot)) continue;
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

/// Two instances of different parts created with one section: the keys one reads, the other refuses.
fn checkSections(s: *State, report: *Report) void {
    for (s.instances.items, 0..) |*a, i| {
        const sa = a.section orelse continue;
        for (s.instances.items[i + 1 ..]) |*b| {
            const sb = b.section orelse continue;
            if (!std.mem.eql(u8, sa, sb) or std.mem.eql(u8, a.part_name.?, b.part_name.?)) continue;
            report.add(A.KE_ASSEMBLY_FAILURE_SHARED_SECTION, b.name, sb, "{s} ({s}) and {s} ({s}) are both created with the section {s}", .{ a.name, a.part_name.?, b.name, b.part_name.?, sb });
        }
    }
}

fn plan(s: *State, report: *Report) R.Error!void {
    var edges: std.ArrayListUnmanaged([2]usize) = .empty;
    for (s.instances.items, 0..) |*self, at| {
        for (self.slots) |targets| for (targets) |t| try edges.append(s.names(), .{ t, at });
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
    for (s.problems.items) |p| report.add(p.failure, p.instance, p.name, "{s}", .{p.detail});
    for (s.instances.items) |*self| {
        if (self.isExternal()) continue;
        const part_name = self.part_name orelse {
            report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, self.name, null, "{s} is bound or ordered but never declared", .{self.name});
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
    }
    checkSections(s, report);
    var defaults = s.defaults.iterator();
    while (defaults.next()) |d| if (s.by_name.get(d.value_ptr.*) == null)
        report.add(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME, null, d.key_ptr.*, "the default of {s} is {s}, which is no instance", .{ d.key_ptr.*, d.value_ptr.* });
    if (report.count == 0) try plan(s, report);
    if (report.count > 0) return error.Unresolved;
    setLogs(s);
    s.resolved = true;
}

fn make(s: *State, at: usize) R.Error!void {
    const self = &s.instances.items[at];
    const part = self.part.?;
    const bound = try s.names().alloc(P.ke_part_bound, self.slots.len);
    const slots = slotsOf(part);
    for (self.slots, 0..) |targets, k| {
        const refs = try s.names().alloc(?*anyopaque, targets.len);
        for (targets, 0..) |t, i| refs[i] = s.instances.items[t].refFor(std.mem.span(slots[k].contract.?));
        bound[k] = .{ .instances = if (refs.len > 0) @ptrCast(refs.ptr) else null, .positions = if (refs.len > 0) &self.positions[k][0] else null, .count = refs.len };
    }
    var settings: ?*abi_settings.c.ke_settings = &empty_settings;
    if (self.section) |section| try R.check(s.configuration.section.?(s.configuration, section.ptr, &settings));
    var made: P.ke_owner = undefined;
    R.check(part.create.?(part, if (bound.len > 0) &bound[0] else null, settings, &made)) catch |err| {
        log.warn("creating {s}, an instance of {s}, failed: {t}", .{ self.name, self.part_name.?, err });
        return err;
    };
    self.made = made;
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
        if (s.instances.items[at].isExternal()) continue;
        try make(s, at);
        if (s.waiting != null) {
            pumpAll(s);
            return error.Pending;
        }
    }
}

/// Slot `get`.
fn get(self: ?*A.ke_assembly, name: ?[*:0]const u8, contract: ?[*:0]const u8, out_instance: ?*?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const out = out_instance orelse return R.code(error.InvalidArgument);
    const wanted = std.mem.span(contract orelse return R.code(error.InvalidArgument));
    const instance = s.instanceOf(std.mem.span(name orelse return R.code(error.InvalidArgument))) orelse return R.code(error.NotFound);
    out.* = instance.refFor(wanted) orelse return R.code(error.NotFound);
    return R.ok;
}

/// The settings of an instance declared with no section: no key and no child.
var empty_settings: abi_settings.c.ke_settings = .{ .get_bool = emptyBool, .get_int = emptyInt, .get_double = emptyDouble, .get_string = emptyString, .for_each_key = emptyList, .child = emptyChild, .for_each_child = emptyList };

fn emptyBool(_: ?*abi_settings.c.ke_settings, _: ?[*:0]const u8, _: ?*bool) callconv(.c) abi_result.c.ke_result {
    return R.code(error.NotFound);
}

fn emptyInt(_: ?*abi_settings.c.ke_settings, _: ?[*:0]const u8, _: ?*i64) callconv(.c) abi_result.c.ke_result {
    return R.code(error.NotFound);
}

fn emptyDouble(_: ?*abi_settings.c.ke_settings, _: ?[*:0]const u8, _: ?*f64) callconv(.c) abi_result.c.ke_result {
    return R.code(error.NotFound);
}

fn emptyString(_: ?*abi_settings.c.ke_settings, _: ?[*:0]const u8, _: ?*?[*:0]const u8) callconv(.c) abi_result.c.ke_result {
    return R.code(error.NotFound);
}

fn emptyList(_: ?*abi_settings.c.ke_settings, _: abi_settings.c.ke_settings_key_func, _: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    return R.ok;
}

fn emptyChild(_: ?*abi_settings.c.ke_settings, _: ?[*:0]const u8, out: ?*?*abi_settings.c.ke_settings) callconv(.c) abi_result.c.ke_result {
    (out orelse return R.code(error.InvalidArgument)).* = &empty_settings;
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
        .api = .{ .handle = null, .route_log = routeLog, .add_part = addPart, .add_instance = addInstance, .add_external = addExternal, .bind = bind, .order = order, .set_default = setDefault, .resolve = resolve, .advance = advance, .get = get },
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
    var pumps: usize = 0;
    var logs_set: usize = 0;
    var ready_done = true;
    var seen_settings: ?*abi_settings.c.ke_settings = null;
    var seen_positions: [2][4]usize = undefined;

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

fn thingCreate(self: ?*const P.ke_part, bound: ?*const P.ke_part_bound, settings: ?*abi_settings.c.ke_settings, out: ?*P.ke_owner) callconv(.c) abi_result.c.ke_result {
    const part = self.?;
    const name = std.mem.span(part.name.?);
    if (Probe.fail_on) |f| if (std.mem.eql(u8, f, name)) return R.code(error.Io);
    if (bound) |b| {
        const all: [*]const P.ke_part_bound = @ptrCast(b);
        for (0..@min(part.slot_count, 2)) |k| if (all[k].count > 0) for (@as([*]const usize, @ptrCast(all[k].positions.?))[0..all[k].count], 0..) |pos, i| {
            Probe.seen_positions[k][i] = pos;
        };
        const first: *const P.ke_part_bound = b;
        Probe.seen_count = first.count;
        if (first.count > 0) for (@as([*]const ?*anyopaque, @ptrCast(first.instances))[0..first.count], 0..) |r, i| {
            Probe.seen_slots[i] = r;
        };
    }
    Probe.seen_settings = settings;
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

const front_and_back = [_]P.ke_part_slot{
    .{ .name = "front", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_MANY },
    .{ .name = "back", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_MANY },
};
const gearbox = P.ke_part{ .name = "gearbox", .slots = &front_and_back[0], .slot_count = 2, .create = thingCreate };
const one_gear = [_]P.ke_part_slot{.{ .name = "gear", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_ONE }};
const many_gears = [_]P.ke_part_slot{.{ .name = "gears", .contract = "ke_gear", .cardinality = P.KE_PART_CARDINALITY_MANY }};

const gear_contract = [_]?[*:0]const u8{"ke_gear"};
const wheel_contract = [_]?[*:0]const u8{"ke_wheel"};
const axle_contract = [_]?[*:0]const u8{"ke_axle"};
const gear_a = P.ke_part{ .name = "gear_a", .provides = &gear_contract[0], .provides_count = 1, .create = thingCreate, .set_log = countLog };
const gear_b = P.ke_part{ .name = "gear_b", .provides = &gear_contract[0], .provides_count = 1, .create = thingCreate, .set_log = countLog };
const gear_slow = P.ke_part{ .name = "gear_slow", .provides = &gear_contract[0], .provides_count = 1, .create = thingCreate, .ready = readyProbe, .pump = pumpProbe };
const wheel = P.ke_part{ .name = "wheel", .provides = &wheel_contract[0], .provides_count = 1, .slots = &one_gear[0], .slot_count = 1, .create = thingCreate };
const axle = P.ke_part{ .name = "axle", .provides = &axle_contract[0], .provides_count = 1, .slots = &many_gears[0], .slot_count = 1, .create = thingCreate };
const loop_wheel = P.ke_part{ .name = "loop_wheel", .provides = &gear_contract[0], .provides_count = 1, .slots = &one_gear[0], .slot_count = 1, .create = thingCreate };

const Rig = struct {
    cfg: zsub.For(abi_configuration.c.ke_configuration),
    settings: abi_settings.c.ke_settings,
    handle: A.ke_assembly_handle,
    failures: [16]A.ke_assembly_failure = undefined,
    failure_count: usize = 0,
    details: [16][256]u8 = undefined,
    detail_lengths: [16]usize = undefined,

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

    fn ref(rig: *Rig, name: [*:0]const u8, contract: [*:0]const u8) !?*anyopaque {
        var out: ?*anyopaque = null;
        try R.check(rig.a().get.?(rig.a(), name, contract, &out));
        return out;
    }

    fn thing(rig: *Rig, name: [*:0]const u8, contract: [*:0]const u8) !*Thing {
        return @ptrCast(@alignCast((try rig.ref(name, contract)).?));
    }

    fn deinit(rig: *Rig) void {
        rig.handle.destroy.?(rig.handle.ref);
        rig.cfg.deinit();
    }

    fn record(ctx: ?*anyopaque, failure: A.ke_assembly_failure, _: ?[*:0]const u8, _: ?[*:0]const u8, detail: ?[*:0]const u8) callconv(.c) void {
        const rig: *Rig = @ptrCast(@alignCast(ctx.?));
        rig.failures[rig.failure_count] = failure;
        const text = std.mem.span(detail.?);
        const kept = @min(text.len, rig.details[rig.failure_count].len);
        @memcpy(rig.details[rig.failure_count][0..kept], text[0..kept]);
        rig.detail_lengths[rig.failure_count] = kept;
        rig.failure_count += 1;
    }

    fn told(rig: *const Rig, needle: []const u8) bool {
        for (0..rig.failure_count) |i| if (std.mem.indexOf(u8, rig.details[i][0..rig.detail_lengths[i]], needle) != null) return true;
        return false;
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
    try testing.expectEqual(try rig.ref("cog", "ke_gear"), Probe.seen_slots[0]);
    try testing.expectEqual(R.code(error.NotFound), rig.a().get.?(rig.a(), "cog", "ke_wheel", &Probe.seen_slots[1]));
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
    try testing.expectEqual(try rig.ref("b", "ke_gear"), (try rig.thing("front", "ke_wheel")).first);
    try testing.expectEqual(try rig.ref("a", "ke_gear"), (try rig.thing("rear", "ke_wheel")).first);
}

test "every reason a composition cannot be assembled is reported together, and nothing is created" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&wheel);
    try rig.part(&gear_a);
    try rig.part(&gear_b);
    try rig.instance("lonely", "wheel");
    try rig.instance("a", "gear_a");
    try rig.instance("b", "gear_b");
    try rig.instance("ghost", "no_such_part");
    try R.check(rig.a().bind.?(rig.a(), "a", "gear", "b"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_AMBIGUOUS));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNKNOWN_PART));
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_UNKNOWN_NAME));
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
    try testing.expectEqual(@as(usize, 2), Probe.seen_count);
    try testing.expectEqual(try rig.ref("second", "ke_gear"), Probe.seen_slots[0]);

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

test "a name taken twice is reported by resolve with the other reasons, and nothing is gathered after resolve" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gear_a);
    try rig.part(&gear_a);
    try rig.instance("a", "gear_a");
    try rig.instance("a", "gear_a");
    var outside = Thing{ .name = "outside" };
    try R.check(rig.a().add_external.?(rig.a(), "a", "ke_gear", &outside));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expectEqual(@as(usize, 3), rig.failure_count);
    try testing.expect(rig.reported(A.KE_ASSEMBLY_FAILURE_DUPLICATE));

    var done: Rig = undefined;
    try done.init();
    defer done.deinit();
    try done.part(&gear_a);
    try done.instance("a", "gear_a");
    try R.check(done.resolve());
    try testing.expectEqual(R.code(error.NotSupported), done.a().add_instance.?(done.a(), "b", "gear_a", "b"));
    try testing.expectEqual(R.code(error.NotSupported), done.resolve());
}

test "a slot that takes many takes only what the composition binds, none when nothing is" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&axle);
    try rig.part(&gear_a);
    try rig.instance("shaft", "axle");
    try rig.instance("cog", "gear_a");
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try testing.expectEqual(@as(usize, 0), Probe.seen_count);
}

test "a reason names what exists: the instances providing a slot's contract, a part's slots, the ambiguous candidates" {
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
    try R.check(rig.a().bind.?(rig.a(), "front", "gear", "c"));
    try R.check(rig.a().bind.?(rig.a(), "front", "tyre", "a"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, rig.resolve());
    try testing.expect(rig.told("ke_gear is provided by a, b"));
    try testing.expect(rig.told("it has gear"));
    try testing.expect(rig.told("ke_gear and a, b provide it"));
}

test "an instance declared with no section is created with empty settings, and parts sharing a section are reported" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gear_a);
    try R.check(rig.a().add_instance.?(rig.a(), "a", "gear_a", null));
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    const given = Probe.seen_settings.?;
    var value: i64 = 0;
    try testing.expectEqual(R.code(error.NotFound), given.get_int.?(given, "anything", &value));
    try rig.cfg.received(.section).never();

    var shared: Rig = undefined;
    try shared.init();
    defer shared.deinit();
    try shared.part(&gear_a);
    try shared.part(&gear_b);
    try R.check(shared.a().add_instance.?(shared.a(), "one", "gear_a", "gears"));
    try R.check(shared.a().add_instance.?(shared.a(), "two", "gear_a", "gears"));
    try R.check(shared.a().add_instance.?(shared.a(), "three", "gear_b", "gears"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, shared.resolve());
    try testing.expectEqual(@as(usize, 2), shared.failure_count);
    try testing.expect(shared.reported(A.KE_ASSEMBLY_FAILURE_SHARED_SECTION));
}

const Pair = struct { gear: Thing = .{ .name = "pair-gear" }, wheel: Thing = .{ .name = "pair-wheel" } };
var pair: Pair = .{};

fn pairCreate(_: ?*const P.ke_part, _: ?*const P.ke_part_bound, _: ?*abi_settings.c.ke_settings, out: ?*P.ke_owner) callconv(.c) abi_result.c.ke_result {
    out.?.* = .{ .ref = &pair, .destroy = null };
    return R.ok;
}

fn pairProvided(instance: ?*anyopaque, index: usize) callconv(.c) ?*anyopaque {
    const p: *Pair = @ptrCast(@alignCast(instance.?));
    return if (index == 0) &p.gear else &p.wheel;
}

const pair_contracts = [_]?[*:0]const u8{ "ke_gear", "ke_wheel" };
const gear_and_wheel = P.ke_part{ .name = "gear_and_wheel", .provides = &pair_contracts[0], .provides_count = 2, .create = pairCreate, .provided = pairProvided };

test "an instance providing several contracts hands each slot the vtable of its contract, and so does an external" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gear_and_wheel);
    try rig.part(&wheel);
    try rig.instance("both", "gear_and_wheel");
    try rig.instance("front", "wheel");
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try testing.expectEqual(@as(?*anyopaque, &pair.gear), Probe.seen_slots[0]);
    try testing.expectEqual(@as(?*anyopaque, &pair.wheel), try rig.ref("both", "ke_wheel"));

    var outside: Rig = undefined;
    try outside.init();
    defer outside.deinit();
    try outside.part(&wheel);
    var gear = Thing{ .name = "gear" };
    var spare = Thing{ .name = "spare" };
    try R.check(outside.a().add_external.?(outside.a(), "given", "ke_gear", &gear));
    try R.check(outside.a().add_external.?(outside.a(), "given", "ke_axle", &spare));
    try outside.instance("front", "wheel");
    try R.check(outside.resolve());
    try R.check(outside.a().advance.?(outside.a()));
    try testing.expectEqual(@as(?*anyopaque, &gear), Probe.seen_slots[0]);
    try testing.expectEqual(@as(?*anyopaque, &spare), try outside.ref("given", "ke_axle"));
}

test "instances ordered across slots receive positions in that order, each slot's own order kept, and contradicting orders are a cycle" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    try rig.part(&gearbox);
    try rig.part(&gear_a);
    try rig.instance("box", "gearbox");
    try rig.instance("a", "gear_a");
    try rig.instance("b", "gear_a");
    try rig.instance("c", "gear_a");
    try R.check(rig.a().bind.?(rig.a(), "box", "front", "a"));
    try R.check(rig.a().bind.?(rig.a(), "box", "front", "c"));
    try R.check(rig.a().bind.?(rig.a(), "box", "back", "b"));
    try R.check(rig.a().order.?(rig.a(), "box", "front", "a", "c"));
    try R.check(rig.a().order.?(rig.a(), "box", null, "a", "b"));
    try R.check(rig.a().order.?(rig.a(), "box", null, "b", "c"));
    try R.check(rig.resolve());
    try R.check(rig.a().advance.?(rig.a()));
    try testing.expectEqual([2]usize{ 0, 2 }, Probe.seen_positions[0][0..2].*);
    try testing.expectEqual(@as(usize, 1), Probe.seen_positions[1][0]);

    var contradicting: Rig = undefined;
    try contradicting.init();
    defer contradicting.deinit();
    try contradicting.part(&gearbox);
    try contradicting.part(&gear_a);
    try contradicting.instance("box", "gearbox");
    try contradicting.instance("a", "gear_a");
    try contradicting.instance("b", "gear_a");
    try R.check(contradicting.a().bind.?(contradicting.a(), "box", "front", "a"));
    try R.check(contradicting.a().bind.?(contradicting.a(), "box", "back", "b"));
    try R.check(contradicting.a().order.?(contradicting.a(), "box", null, "a", "b"));
    try R.check(contradicting.a().order.?(contradicting.a(), "box", null, "b", "a"));
    try testing.expectEqual(abi_assembly.c.KE_RESULT_ASSEMBLY_UNRESOLVED, contradicting.resolve());
    try testing.expect(contradicting.reported(A.KE_ASSEMBLY_FAILURE_CYCLE));
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
