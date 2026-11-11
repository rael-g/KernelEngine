//! The `ke_scheduler` plugin: it orders the systems of each phase by what they touch and the sets
//! they join, and runs one phase at a time, wave by wave, across a task pool, over an ecs it borrows.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_scheduler").logFn };

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_scheduler = @import("abi_scheduler");
const abi_task_pool = @import("abi_task_pool");
const heap = @import("heap");
const order = @import("scheduler_order.zig");
const body = @import("scheduler_commands.zig");

const R = @import("result").Result(.{});
const log = std.log.scoped(.scheduler);

const c = abi_scheduler.c;
const gpa = heap.gpa;
const Id = c.ke_component_id;
const SystemId = c.ke_scheduler_system_id;

const Query = struct {
    terms: []const c.ke_id_access,
    id: abi_ecs.c.ke_query_id = abi_ecs.c.KE_QUERY_INVALID,
    bound: bool = false,
};

/// A system as the scheduler holds it: its own copy of what was registered, in `arena`, the access
/// the conflict rule reads, which merges its query terms with `explicit`, and the segments its
/// queries resolve to. It is linked through `next` while it waits on `State.pending`.
const System = struct {
    arena: std.heap.ArenaAllocator,
    id: SystemId,
    phase: c.ke_phase_id,
    name: [:0]const u8,
    user_data: ?*anyopaque,
    execute: c.ke_scheduler_execute_fn,
    per_entity: bool,
    exclusive: bool,
    access: []const c.ke_id_access,
    explicit: []const c.ke_id_access,
    queries: []Query,
    query_terms: []const []const c.ke_id_access,
    segments: []body.Segments,
    sets: []const c.ke_set_id,
    next: ?*System = null,

    fn destroy(s: *System) void {
        for (s.segments) |*seg| seg.deinit();
        s.arena.deinit();
        gpa.destroy(s);
    }
};

/// A phase and the order last built for it, kept until a registration touches the phase. `systems`
/// are the phase's systems in registration order, and `waves` and `culled` run beside them.
const Phase = struct {
    name: [:0]u8,
    built: bool = false,
    systems: []*System = &.{},
    waves: []u32 = &.{},
    culled: []bool = &.{},
    wave_count: u32 = 0,
    failure: order.Problem = .none,
    ambiguity: order.Problem = .none,

    fn clear(p: *Phase) void {
        gpa.free(p.systems);
        gpa.free(p.waves);
        gpa.free(p.culled);
        p.* = .{ .name = p.name };
    }
};

const Set = struct {
    name: [:0]u8,
    phase: c.ke_phase_id,
    after: []c.ke_set_id,
};

const Lifetime = struct { id: Id, lifetime: c.ke_lifetime };

const Removal = struct { id: SystemId, next: ?*Removal = null };

/// One task of a wave: one slice of one system, with its own context and queue. The task pool is
/// handed its address, so it stays in place until the wave has been waited for.
const Package = struct {
    context: body.Context,
    queue: body.Queue = .{},
    system: *System,
    dt: f32,
    task: ?*abi_task_pool.c.ke_task = null,
};

/// The state behind the `ke_scheduler` handle, whose `api.handle` points back at it. Phases, sets,
/// systems and declarations change only while no run is in flight: a system registered or removed
/// from a body waits on the lock-free `pending` and `removals` lists until the next run applies
/// them, in call order, and every other change is refused from a body.
const State = struct {
    api: c.ke_scheduler,
    ecs: *abi_ecs.c.ke_ecs,
    pool: *abi_task_pool.c.ke_task_pool,
    phases: std.ArrayList(Phase) = .empty,
    sets: std.ArrayList(Set) = .empty,
    systems: std.ArrayList(*System) = .empty,
    lifetimes: std.ArrayList(Lifetime) = .empty,
    exclusive: std.ArrayList(order.Exclusive) = .empty,
    packages: std.ArrayList(Package) = .empty,
    next_system: std.atomic.Value(SystemId) = .init(0),
    running: std.atomic.Value(bool) = .init(false),
    pending: std.atomic.Value(?*System) = .init(null),
    removals: std.atomic.Value(?*Removal) = .init(null),
    host_queue: body.Queue = .{},
    host: body.Context,

    fn dirtyPhase(s: *State, phase: c.ke_phase_id) void {
        s.phases.items[phase].clear();
    }

    fn dirtyAll(s: *State) void {
        for (s.phases.items) |*p| p.clear();
    }

    fn refuseInRun(s: *State) R.Error!void {
        if (s.running.load(.acquire)) return reject(error.NotSupported, "the call is refused from a body");
    }
};

fn stateOf(self: ?*c.ke_scheduler) ?*State {
    return @alignCast(@fieldParentPtr("api", self orelse return null));
}

fn reject(err: R.Error, comptime why: []const u8) R.Error {
    log.warn(why, .{});
    return err;
}

fn failed(comptime slot: []const u8, err: R.Error) abi_result.c.ke_result {
    log.warn(slot ++ " failed: {t}", .{err});
    return R.code(err);
}

/// Slot `register_phase`.
fn registerPhase(self: ?*c.ke_scheduler, desc: ?*const c.ke_phase_desc, out_id: ?*c.ke_phase_id) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("register_phase", error.InvalidArgument);
    const out = out_id orelse return failed("register_phase", error.InvalidArgument);
    out.* = addPhase(s, desc orelse return failed("register_phase", error.InvalidArgument)) catch |err| return failed("register_phase", err);
    return R.ok;
}

fn addPhase(s: *State, desc: *const c.ke_phase_desc) R.Error!c.ke_phase_id {
    try s.refuseInRun();
    const name = desc.name orelse return reject(error.InvalidArgument, "a phase needs a name");
    const copy = try gpa.dupeZ(u8, std.mem.span(name));
    errdefer gpa.free(copy);
    try s.phases.append(gpa, .{ .name = copy });
    return @intCast(s.phases.items.len - 1);
}

/// Slot `register_set`.
fn registerSet(self: ?*c.ke_scheduler, desc: ?*const c.ke_set_desc, out_id: ?*c.ke_set_id) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("register_set", error.InvalidArgument);
    const out = out_id orelse return failed("register_set", error.InvalidArgument);
    out.* = addSet(s, desc orelse return failed("register_set", error.InvalidArgument)) catch |err| return failed("register_set", err);
    return R.ok;
}

fn addSet(s: *State, desc: *const c.ke_set_desc) R.Error!c.ke_set_id {
    try s.refuseInRun();
    const name = desc.name orelse return reject(error.InvalidArgument, "a set needs a name");
    if (desc.phase >= s.phases.items.len) return reject(error.InvalidArgument, "a set names an unknown phase");
    const after: []const c.ke_set_id = if (desc.after_count == 0) &.{} else (desc.after orelse return reject(error.InvalidArgument, "a set counts sets it does not point at"))[0..desc.after_count];
    for (after) |a| {
        if (a >= s.sets.items.len or s.sets.items[a].phase != desc.phase) return reject(error.InvalidArgument, "a set follows a set of another phase or an unknown one");
    }
    const copy = try gpa.dupeZ(u8, std.mem.span(name));
    errdefer gpa.free(copy);
    const after_copy = try gpa.dupe(c.ke_set_id, after);
    errdefer gpa.free(after_copy);
    try s.sets.append(gpa, .{ .name = copy, .phase = desc.phase, .after = after_copy });
    s.dirtyPhase(desc.phase);
    return @intCast(s.sets.items.len - 1);
}

fn validAccess(list: []const c.ke_id_access) bool {
    const known = c.KE_SCHEDULER_ACCESS_READ | c.KE_SCHEDULER_ACCESS_WRITE;
    for (list) |a| {
        if (a.access == 0 or (a.access & ~@as(c.ke_scheduler_access, known)) != 0) return false;
    }
    return true;
}

fn merge(list: *std.ArrayList(c.ke_id_access), a: std.mem.Allocator, want: c.ke_id_access) !void {
    for (list.items) |*have| {
        if (have.id == want.id) {
            have.access |= want.access;
            return;
        }
    }
    try list.append(a, want);
}

/// Copies a registration into a new system that owns everything it was given.
fn makeSystem(s: *State, desc: *const c.ke_system_desc) R.Error!*System {
    if (desc.execute == null) return reject(error.InvalidArgument, "a system needs a body");
    const name = desc.name orelse return reject(error.InvalidArgument, "a system needs a name");
    if (desc.phase >= s.phases.items.len) return reject(error.InvalidArgument, "a system names an unknown phase");
    const queries: []const c.ke_query_desc = if (desc.query_count == 0) &.{} else (desc.queries orelse return reject(error.InvalidArgument, "a system counts queries it does not point at"))[0..desc.query_count];
    const explicit: []const c.ke_id_access = if (desc.access_count == 0) &.{} else (desc.access orelse return reject(error.InvalidArgument, "a system counts access it does not point at"))[0..desc.access_count];
    const sets: []const c.ke_set_id = if (desc.set_count == 0) &.{} else (desc.sets orelse return reject(error.InvalidArgument, "a system counts sets it does not point at"))[0..desc.set_count];
    for (queries) |q| {
        if (q.term_count == 0 or q.terms == null) return reject(error.InvalidArgument, "a query declares no terms");
        if (!validAccess(q.terms.?[0..q.term_count])) return reject(error.InvalidArgument, "a query term has no known access");
    }
    if (!validAccess(explicit)) return reject(error.InvalidArgument, "an access entry has no known access");
    for (sets) |set| {
        if (set >= s.sets.items.len or s.sets.items[set].phase != desc.phase) return reject(error.InvalidArgument, "a system joins a set of another phase or an unknown one");
    }

    const system = try gpa.create(System);
    errdefer gpa.destroy(system);
    system.arena = .init(gpa);
    errdefer system.arena.deinit();
    const a = system.arena.allocator();

    const owned_queries = try a.alloc(Query, queries.len);
    const query_terms = try a.alloc([]const c.ke_id_access, queries.len);
    var access: std.ArrayList(c.ke_id_access) = .empty;
    for (queries, owned_queries, query_terms) |q, *owned, *terms| {
        const copy = try a.dupe(c.ke_id_access, q.terms.?[0..q.term_count]);
        owned.* = .{ .terms = copy };
        terms.* = copy;
        for (copy) |t| try merge(&access, a, t);
    }
    for (explicit) |e| try merge(&access, a, e);
    const segments = try a.alloc(body.Segments, queries.len);
    @memset(segments, .{});

    system.* = .{
        .arena = system.arena,
        .id = 0,
        .phase = desc.phase,
        .name = try a.dupeZ(u8, std.mem.span(name)),
        .user_data = desc.user_data,
        .execute = desc.execute,
        .per_entity = desc.per_entity,
        .exclusive = desc.exclusive,
        .access = access.items,
        .explicit = try a.dupe(c.ke_id_access, explicit),
        .queries = owned_queries,
        .query_terms = query_terms,
        .segments = segments,
        .sets = try a.dupe(c.ke_set_id, sets),
    };
    return system;
}

/// Slot `register_system`. From a body, the system waits on `State.pending` for the next run.
fn registerSystem(self: ?*c.ke_scheduler, desc: ?*const c.ke_system_desc, out_id: ?*SystemId) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("register_system", error.InvalidArgument);
    const out = out_id orelse return failed("register_system", error.InvalidArgument);
    out.* = addSystem(s, desc orelse return failed("register_system", error.InvalidArgument)) catch |err| return failed("register_system", err);
    return R.ok;
}

fn addSystem(s: *State, desc: *const c.ke_system_desc) R.Error!SystemId {
    const system = try makeSystem(s, desc);
    system.id = s.next_system.fetchAdd(1, .monotonic) + 1;
    if (s.running.load(.acquire)) {
        var head = s.pending.load(.acquire);
        while (true) {
            system.next = head;
            head = s.pending.cmpxchgWeak(head, system, .release, .acquire) orelse return system.id;
        }
    }
    s.systems.append(gpa, system) catch |err| {
        system.destroy();
        return err;
    };
    s.dirtyPhase(system.phase);
    return system.id;
}

/// Slot `unregister_system`. From a body, the removal waits on `State.removals` for the next run,
/// where an id already removed is dropped without a failure.
fn unregisterSystem(self: ?*c.ke_scheduler, id: SystemId) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("unregister_system", error.InvalidArgument);
    removeSystem(s, id) catch |err| return failed("unregister_system", err);
    return R.ok;
}

fn removeSystem(s: *State, id: SystemId) R.Error!void {
    if (id == 0 or id > s.next_system.load(.monotonic)) return reject(error.NotFound, "no system has that id");
    if (s.running.load(.acquire)) {
        const removal = try gpa.create(Removal);
        removal.* = .{ .id = id };
        var head = s.removals.load(.acquire);
        while (true) {
            removal.next = head;
            head = s.removals.cmpxchgWeak(head, removal, .release, .acquire) orelse return;
        }
    }
    if (!removeNow(s, id)) return reject(error.NotFound, "no system has that id");
}

fn removeNow(s: *State, id: SystemId) bool {
    for (s.systems.items, 0..) |system, i| {
        if (system.id != id) continue;
        s.dirtyPhase(system.phase);
        _ = s.systems.orderedRemove(i);
        system.destroy();
        return true;
    }
    return false;
}

/// Applies what bodies registered and removed during the last run, in call order, so a removal of
/// a system registered in the same run still finds it.
fn applyPending(s: *State) void {
    var stack = s.pending.swap(null, .acq_rel);
    var reversed: ?*System = null;
    while (stack) |system| {
        stack = system.next;
        system.next = reversed;
        reversed = system;
    }
    while (reversed) |system| {
        reversed = system.next;
        system.next = null;
        s.systems.append(gpa, system) catch {
            log.warn("a system registered from a body is dropped: out of memory", .{});
            system.destroy();
            continue;
        };
        s.dirtyPhase(system.phase);
    }

    var removals = s.removals.swap(null, .acq_rel);
    var ordered: ?*Removal = null;
    while (removals) |r| {
        removals = r.next;
        r.next = ordered;
        ordered = r;
    }
    while (ordered) |r| {
        ordered = r.next;
        _ = removeNow(s, r.id);
        gpa.destroy(r);
    }
}

/// Slot `declare_lifetime`.
fn declareLifetime(self: ?*c.ke_scheduler, id: Id, lifetime: c.ke_lifetime) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("declare_lifetime", error.InvalidArgument);
    setLifetime(s, id, lifetime) catch |err| return failed("declare_lifetime", err);
    return R.ok;
}

fn setLifetime(s: *State, id: Id, lifetime: c.ke_lifetime) R.Error!void {
    try s.refuseInRun();
    if (lifetime != c.KE_LIFETIME_PERSISTENT and lifetime != c.KE_LIFETIME_PHASE) return reject(error.InvalidArgument, "unknown lifetime");
    s.dirtyAll();
    for (s.lifetimes.items) |*l| {
        if (l.id != id) continue;
        l.lifetime = lifetime;
        return;
    }
    try s.lifetimes.append(gpa, .{ .id = id, .lifetime = lifetime });
}

/// Slot `declare_exclusive`.
fn declareExclusive(self: ?*c.ke_scheduler, group: Id, member: Id) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("declare_exclusive", error.InvalidArgument);
    addExclusive(s, group, member) catch |err| return failed("declare_exclusive", err);
    return R.ok;
}

fn addExclusive(s: *State, group: Id, member: Id) R.Error!void {
    try s.refuseInRun();
    if (group == member) return reject(error.InvalidArgument, "a group and a different member are required");
    try s.exclusive.append(gpa, .{ .group = group, .member = member });
    s.dirtyAll();
}

/// Builds the order of a phase whose registrations changed since its last build. A cycle is kept
/// as the phase's failure, which `run` and `describe_phase` report until the phase changes.
fn buildPhase(s: *State, index: c.ke_phase_id) R.Error!void {
    const phase = &s.phases.items[index];
    if (phase.built) return;
    phase.clear();

    var systems: std.ArrayList(*System) = .empty;
    errdefer systems.deinit(gpa);
    for (s.systems.items) |system| {
        if (system.phase == index) try systems.append(gpa, system);
    }

    const set_map = try gpa.alloc(u32, s.sets.items.len);
    defer gpa.free(set_map);
    var set_ids: std.ArrayList(c.ke_set_id) = .empty;
    defer set_ids.deinit(gpa);
    for (s.sets.items, 0..) |set, i| {
        if (set.phase != index) continue;
        set_map[i] = @intCast(set_ids.items.len);
        try set_ids.append(gpa, @intCast(i));
    }
    const set_count = set_ids.items.len;
    const local_after = try gpa.alloc([]u32, set_count);
    defer gpa.free(local_after);
    var made: usize = 0;
    defer for (local_after[0..made]) |list| gpa.free(list);
    for (set_ids.items, local_after) |global, *list| {
        const after = s.sets.items[global].after;
        list.* = try gpa.alloc(u32, after.len);
        made += 1;
        for (after, list.*) |a, *l| l.* = set_map[a];
    }
    const follows = try gpa.alloc(bool, set_count * set_count);
    defer gpa.free(follows);
    const cycle = order.closeSets(@ptrCast(local_after), follows);

    const nodes = try gpa.alloc(order.Node, systems.items.len);
    defer gpa.free(nodes);
    var local_sets: std.ArrayList(u32) = .empty;
    defer local_sets.deinit(gpa);
    for (systems.items) |system| {
        for (system.sets) |set| try local_sets.append(gpa, set_map[set]);
    }
    var at: usize = 0;
    for (systems.items, nodes) |system, *node| {
        node.* = .{
            .name = system.name,
            .exclusive = system.exclusive,
            .access = system.access,
            .explicit = system.explicit,
            .queries = system.query_terms,
            .sets = local_sets.items[at..][0..system.sets.len],
        };
        at += system.sets.len;
    }

    var short_lived: std.ArrayList(Id) = .empty;
    defer short_lived.deinit(gpa);
    for (s.lifetimes.items) |l| {
        if (l.lifetime == c.KE_LIFETIME_PHASE) try short_lived.append(gpa, l.id);
    }

    const waves = try gpa.alloc(u32, nodes.len);
    errdefer gpa.free(waves);
    const culled = try gpa.alloc(bool, nodes.len);
    errdefer gpa.free(culled);
    order.cull(nodes, short_lived.items, culled);
    const built: order.Order = if (cycle) |set| .{ .failure = .{ .cycle = s.sets.items[set_ids.items[set]].name } } else order.order(nodes, follows, set_count, s.exclusive.items, waves);
    if (built.failure == .out_of_memory) return error.OutOfMemory;

    phase.* = .{
        .name = phase.name,
        .built = true,
        .systems = try systems.toOwnedSlice(gpa),
        .waves = waves,
        .culled = culled,
        .wave_count = built.wave_count,
        .failure = built.failure,
        .ambiguity = built.ambiguity,
    };
}

/// The failure a phase's order holds, logged with the names involved.
fn orderFailure(phase: *const Phase, refuse_ambiguity: bool) R.Error!void {
    switch (phase.failure) {
        .none, .out_of_memory, .ambiguity => {},
        .cycle => |name| {
            log.warn("the order of phase {s} has a cycle through {s}", .{ phase.name, name });
            return error.General;
        },
    }
    if (!refuse_ambiguity) return;
    switch (phase.ambiguity) {
        .ambiguity => |a| {
            log.warn("in phase {s}, {s} and {s} both write {d} with no order between them", .{ phase.name, a.first, a.second, a.id });
            return error.General;
        },
        else => {},
    }
}

/// Slot `build`.
fn build(self: ?*c.ke_scheduler, refuse_ambiguity: bool) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("build", error.InvalidArgument);
    buildAll(s, refuse_ambiguity) catch |err| return failed("build", err);
    return R.ok;
}

fn buildAll(s: *State, refuse_ambiguity: bool) R.Error!void {
    try s.refuseInRun();
    for (s.phases.items, 0..) |_, i| {
        try buildPhase(s, @intCast(i));
        try orderFailure(&s.phases.items[i], refuse_ambiguity);
    }
}

/// Slot `describe_phase`. The count is written even when the capacity is too small.
fn describePhase(self: ?*c.ke_scheduler, phase: c.ke_phase_id, out_systems: ?[*]c.ke_system_order, capacity: u32, out_count: ?*u32) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("describe_phase", error.InvalidArgument);
    describe(s, phase, out_systems, capacity, out_count orelse return failed("describe_phase", error.InvalidArgument)) catch |err| return failed("describe_phase", err);
    return R.ok;
}

fn describe(s: *State, index: c.ke_phase_id, out_systems: ?[*]c.ke_system_order, capacity: u32, out_count: *u32) R.Error!void {
    try s.refuseInRun();
    if (index >= s.phases.items.len) return reject(error.InvalidArgument, "describe_phase names an unknown phase");
    try buildPhase(s, index);
    const phase = &s.phases.items[index];
    try orderFailure(phase, false);
    out_count.* = @intCast(phase.systems.len);
    if (phase.systems.len > capacity) return reject(error.InvalidArgument, "the phase holds more systems than the capacity given");
    if (phase.systems.len == 0) return;
    const out = out_systems orelse return reject(error.InvalidArgument, "describe_phase needs an array to write");
    for (phase.systems, phase.waves, phase.culled, out[0..phase.systems.len]) |system, wave, culled, *entry| {
        entry.* = .{ .id = system.id, .wave = wave, .culled = culled };
    }
}

fn bindQueries(s: *State) R.Error!void {
    for (s.systems.items) |system| {
        for (system.queries) |*q| {
            if (q.bound) continue;
            const register = s.ecs.query_register orelse return reject(error.NotSupported, "the ecs registers no query");
            const ids = try gpa.alloc(Id, q.terms.len);
            defer gpa.free(ids);
            for (q.terms, ids) |t, *id| id.* = t.id;
            R.check(register(s.ecs, ids.ptr, ids.len, &q.id)) catch |err| {
                log.warn("the ecs refused a query of {s}", .{system.name});
                return err;
            };
            q.bound = true;
        }
    }
}

fn slicesOf(s: *State, system: *const System) u32 {
    if (!system.per_entity or system.exclusive) return 1;
    const workers = if (s.pool.get_num_workers) |f| f(s.pool) else 1;
    return @max(workers, 1);
}

/// The task pool body of one package.
fn runPackage(data: ?*anyopaque) callconv(.c) abi_result.c.ke_result {
    const pkg: *Package = @ptrCast(@alignCast(data.?));
    return pkg.system.execute.?(&pkg.context.ctx, pkg.system.user_data, pkg.dt);
}

const Failure = struct {
    err: R.Error,
    name: [:0]const u8,
};

fn keepFirst(failure: *?Failure, code: abi_result.c.ke_result, name: [:0]const u8) void {
    if (failure.* != null) return;
    R.check(code) catch |err| {
        failure.* = .{ .err = err, .name = name };
    };
}

/// Slot `run`.
fn run(self: ?*c.ke_scheduler, phase: c.ke_phase_id, dt: f32) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("run", error.InvalidArgument);
    runPhase(s, phase, dt) catch |err| return failed("run", err);
    return R.ok;
}

fn runPhase(s: *State, index: c.ke_phase_id, dt: f32) R.Error!void {
    try s.refuseInRun();
    if (index >= s.phases.items.len) return reject(error.InvalidArgument, "run names an unknown phase");
    applyPending(s);
    s.host_queue.flush(s.ecs) catch |err| {
        log.warn("applying the caller's commands failed", .{});
        return err;
    };
    try bindQueries(s);
    try buildPhase(s, index);
    const phase = &s.phases.items[index];
    try orderFailure(phase, false);

    s.running.store(true, .release);
    defer s.running.store(false, .release);

    var failure: ?Failure = null;
    for (0..phase.wave_count) |w| {
        var count: usize = 0;
        for (phase.systems, phase.waves, phase.culled) |system, wave, culled| {
            if (wave != w or culled) continue;
            for (system.queries, system.segments) |q, *seg| {
                seg.resolve(s.ecs, q.id, q.terms.len) catch |err| {
                    log.warn("resolving a query of {s} failed", .{system.name});
                    return err;
                };
            }
            count += slicesOf(s, system);
        }

        s.packages.clearRetainingCapacity();
        try s.packages.ensureTotalCapacity(gpa, count);
        for (phase.systems, phase.waves, phase.culled) |system, wave, culled| {
            if (wave != w or culled) continue;
            const slices = slicesOf(s, system);
            for (0..slices) |slice| {
                s.packages.appendAssumeCapacity(.{
                    .context = .{ .ecs = s.ecs, .queue = null, .queries = system.segments, .slice_index = @intCast(slice), .slice_count = slices },
                    .system = system,
                    .dt = dt,
                });
            }
        }
        for (s.packages.items) |*pkg| {
            pkg.context.queue = &pkg.queue;
            pkg.context.bind();
        }

        for (s.packages.items) |*pkg| keepFirst(&failure, s.pool.dispatch.?(s.pool, &runPackage, pkg, &pkg.task), pkg.system.name);
        for (s.packages.items) |*pkg| {
            const task = pkg.task orelse continue;
            keepFirst(&failure, s.pool.wait.?(s.pool, task), pkg.system.name);
        }
        for (s.packages.items) |*pkg| {
            pkg.queue.flush(s.ecs) catch |err| {
                if (failure == null) failure = .{ .err = err, .name = pkg.system.name };
            };
            pkg.queue.deinit();
        }
        if (failure != null) break;
    }
    if (failure) |f| {
        log.warn("{s} failed: {t}", .{ f.name, f.err });
        return f.err;
    }
}

/// Slot `commands`.
fn commands(self: ?*c.ke_scheduler) callconv(.c) ?*abi_ecs.c.ke_ecs_commands {
    const s = stateOf(self) orelse return null;
    return &s.host.commands;
}

/// Slot `destroy` of the handle: frees every system, pending or registered, and every declaration.
fn destroy(self: ?*c.ke_scheduler) callconv(.c) void {
    const s = stateOf(self) orelse return;
    applyPending(s);
    for (s.systems.items) |system| system.destroy();
    s.systems.deinit(gpa);
    for (s.phases.items) |*p| {
        p.clear();
        gpa.free(p.name);
    }
    s.phases.deinit(gpa);
    for (s.sets.items) |set| {
        gpa.free(set.name);
        gpa.free(set.after);
    }
    s.sets.deinit(gpa);
    s.lifetimes.deinit(gpa);
    s.exclusive.deinit(gpa);
    s.packages.deinit(gpa);
    s.host_queue.deinit();
    gpa.destroy(s);
}

/// The factory: a scheduler over an ecs and a task pool it borrows and never frees.
export fn ke_scheduler_create(ecs: ?*abi_ecs.c.ke_ecs, task_pool: ?*abi_task_pool.c.ke_task_pool, config: ?*const c.ke_scheduler_config, out_scheduler: ?*c.ke_scheduler_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_scheduler orelse return failed("ke_scheduler_create", error.InvalidArgument);
    out.* = .{};
    if (ecs == null or task_pool == null or config == null) return failed("ke_scheduler_create", reject(error.InvalidArgument, "a scheduler needs an ecs, a task pool and its config"));
    const s = gpa.create(State) catch |err| return failed("ke_scheduler_create", err);
    s.* = .{
        .api = .{
            .register_phase = &registerPhase,
            .register_set = &registerSet,
            .register_system = &registerSystem,
            .unregister_system = &unregisterSystem,
            .declare_lifetime = &declareLifetime,
            .declare_exclusive = &declareExclusive,
            .build = &build,
            .describe_phase = &describePhase,
            .run = &run,
            .commands = &commands,
        },
        .ecs = ecs.?,
        .pool = task_pool.?,
        .host = .{ .ecs = ecs.?, .queue = undefined },
    };
    s.api.handle = s;
    s.host.queue = &s.host_queue;
    s.host.bind();
    out.* = .{ .ref = &s.api, .destroy = &destroy };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

fn inlineDispatch(args: std.meta.ArgsTuple(@typeInfo(@typeInfo(@FieldType(abi_task_pool.c.ke_task_pool, "dispatch")).optional.child).pointer.child)) abi_result.c.ke_result {
    return args[1].?(args[2]);
}

const Rig = struct {
    ecs: zsub.For(abi_ecs.c.ke_ecs),
    pool: zsub.For(abi_task_pool.c.ke_task_pool),
    handle: c.ke_scheduler_handle,
    sched: *c.ke_scheduler,
    phase: c.ke_phase_id,

    fn init(self: *Rig, workers: u32) !void {
        try self.ecs.init();
        _ = self.ecs.when(.query_register).writesFresh(3);
        _ = self.ecs.when(.entity_reserve).writesFresh(1);
        _ = self.ecs.when(.component_size).returns(4);
        try self.pool.init();
        _ = self.pool.when(.dispatch).does(&inlineDispatch);
        _ = self.pool.when(.get_num_workers).returns(workers);
        try R.check(ke_scheduler_create(self.ecs.api(), self.pool.api(), &.{ .reserved = 0 }, &self.handle));
        self.sched = self.handle.ref.?;
        self.phase = try self.addPhase("update");
    }

    fn deinit(self: *Rig) void {
        self.handle.destroy.?(self.sched);
        self.pool.deinit();
        self.ecs.deinit();
    }

    fn addPhase(self: *Rig, name: [*:0]const u8) !c.ke_phase_id {
        var id: c.ke_phase_id = undefined;
        try R.check(self.sched.register_phase.?(self.sched, &.{ .name = name }, &id));
        return id;
    }

    fn addSet(self: *Rig, name: [*:0]const u8, after: []const c.ke_set_id) !c.ke_set_id {
        var id: c.ke_set_id = undefined;
        try R.check(self.sched.register_set.?(self.sched, &.{ .name = name, .phase = self.phase, .after = after.ptr, .after_count = @intCast(after.len) }, &id));
        return id;
    }

    fn add(self: *Rig, desc: c.ke_system_desc) !SystemId {
        var id: SystemId = undefined;
        try R.check(self.sched.register_system.?(self.sched, &desc, &id));
        return id;
    }

    fn run(self: *Rig) !void {
        try R.check(self.sched.run.?(self.sched, self.phase, 0.5));
    }

    fn describe(self: *Rig, out: []c.ke_system_order) !u32 {
        var count: u32 = 0;
        try R.check(self.sched.describe_phase.?(self.sched, self.phase, out.ptr, @intCast(out.len), &count));
        return count;
    }
};

const Probe = struct {
    calls: std.atomic.Value(u32) = .init(0),
    slices: [8]std.atomic.Value(u32) = @splat(.init(0)),
    seen_count: u32 = 0,
    segments: usize = 0,
};

fn counting(ctx: ?*c.ke_scheduler_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const probe: *Probe = @ptrCast(@alignCast(ud.?));
    _ = probe.calls.fetchAdd(1, .monotonic);
    var index: u32 = 0;
    var count: u32 = 0;
    ctx.?.slice.?(ctx, &index, &count);
    probe.seen_count = count;
    _ = probe.slices[index].fetchAdd(1, .monotonic);
    _ = ctx.?.view.?(ctx, 0, &probe.segments);
    return R.ok;
}

fn refusing(_: ?*c.ke_scheduler_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const probe: *Probe = @ptrCast(@alignCast(ud.?));
    _ = probe.calls.fetchAdd(1, .monotonic);
    return R.code(error.Io);
}

fn systemDesc(name: [*:0]const u8, probe: *Probe, phase: c.ke_phase_id) c.ke_system_desc {
    return .{ .name = name, .phase = phase, .user_data = probe, .execute = &counting };
}

fn idAccess(id: Id, mode: c.ke_scheduler_access) c.ke_id_access {
    return .{ .id = id, .access = mode };
}

const read = c.KE_SCHEDULER_ACCESS_READ;
const write = c.KE_SCHEDULER_ACCESS_WRITE;

test "a scheduler with a phase and no system runs it and tears down" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    try rig.run();
}

test "a system runs once per run of its phase and never in another" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    const other = try rig.addPhase("render");
    var here = Probe{};
    var there = Probe{};
    _ = try rig.add(systemDesc("here", &here, rig.phase));
    _ = try rig.add(systemDesc("there", &there, other));
    try rig.run();
    try rig.run();
    try testing.expectEqual(2, here.calls.load(.monotonic));
    try testing.expectEqual(0, there.calls.load(.monotonic));
}

test "a system that does not promise per-entity work runs as one slice" {
    var rig: Rig = undefined;
    try rig.init(4);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(systemDesc("whole", &probe, rig.phase));
    try rig.run();
    try testing.expectEqual(1, probe.calls.load(.monotonic));
    try testing.expectEqual(1, probe.seen_count);
}

test "a per-entity system runs every slice of its set exactly once, one per worker" {
    var rig: Rig = undefined;
    try rig.init(4);
    defer rig.deinit();
    var probe = Probe{};
    var desc = systemDesc("sliced", &probe, rig.phase);
    desc.per_entity = true;
    _ = try rig.add(desc);
    try rig.run();
    try testing.expectEqual(4, probe.calls.load(.monotonic));
    for (probe.slices[0..4]) |s| try testing.expectEqual(1, s.load(.monotonic));
}

test "a system with no body, no name, an unknown phase or a set of another phase is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    var no_body = systemDesc("x", &probe, rig.phase);
    no_body.execute = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &no_body, &id));
    var no_name = systemDesc("x", &probe, rig.phase);
    no_name.name = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &no_name, &id));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &systemDesc("x", &probe, 7), &id));
    const other = try rig.addPhase("render");
    const set = try rig.addSet("opaque", &.{});
    var foreign = systemDesc("x", &probe, other);
    foreign.sets = &.{set};
    foreign.set_count = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &foreign, &id));
}

test "a query declaring no terms, or counting terms it does not point at, is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    const empty = [_]c.ke_query_desc{.{ .terms = null, .term_count = 0 }};
    var desc = systemDesc("x", &probe, rig.phase);
    desc.queries = &empty;
    desc.query_count = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
    desc.queries = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
}

test "an access with no known mode is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    const list = [_]c.ke_id_access{idAccess(1, 0)};
    var desc = systemDesc("x", &probe, rig.phase);
    desc.access = &list;
    desc.access_count = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
    const unknown = [_]c.ke_id_access{idAccess(1, 8)};
    desc.access = &unknown;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
}

test "a registered system keeps its own copy of the name and the access it was given" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var name = "writer".*;
    var list = [_]c.ke_id_access{idAccess(1, write)};
    var desc = systemDesc(&name, &probe, rig.phase);
    desc.access = &list;
    desc.access_count = 1;
    _ = try rig.add(desc);
    @memset(&name, 'x');
    list[0] = idAccess(9, read);
    var reader = systemDesc("reader", &probe, rig.phase);
    const reads_one = [_]c.ke_id_access{idAccess(1, read)};
    reader.access = &reads_one;
    reader.access_count = 1;
    _ = try rig.add(reader);
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(1, out[1].wave);
}

test "a writer of an id runs in a wave before a system that only reads it, and disjoint systems share a wave" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const reads_one = [_]c.ke_id_access{idAccess(1, read)};
    const writes_one = [_]c.ke_id_access{idAccess(1, write)};
    const writes_two = [_]c.ke_id_access{idAccess(2, write)};
    var reader = systemDesc("reader", &probe, rig.phase);
    reader.access = &reads_one;
    reader.access_count = 1;
    var writer = systemDesc("writer", &probe, rig.phase);
    writer.access = &writes_one;
    writer.access_count = 1;
    var other = systemDesc("other", &probe, rig.phase);
    other.access = &writes_two;
    other.access_count = 1;
    const r = try rig.add(reader);
    const w = try rig.add(writer);
    const o = try rig.add(other);
    var out: [3]c.ke_system_order = undefined;
    try testing.expectEqual(3, try rig.describe(&out));
    try testing.expectEqual(c.ke_system_order{ .id = r, .wave = 1, .culled = false }, out[0]);
    try testing.expectEqual(c.ke_system_order{ .id = w, .wave = 0, .culled = false }, out[1]);
    try testing.expectEqual(c.ke_system_order{ .id = o, .wave = 0, .culled = false }, out[2]);
}

test "two writers with no other order run in registration order, and a build refusing ambiguity fails" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const writes_one = [_]c.ke_id_access{idAccess(1, write)};
    var first = systemDesc("first", &probe, rig.phase);
    first.access = &writes_one;
    first.access_count = 1;
    var second = first;
    second.name = "second";
    _ = try rig.add(first);
    _ = try rig.add(second);
    try R.check(rig.sched.build.?(rig.sched, false));
    try testing.expectEqual(R.code(error.General), rig.sched.build.?(rig.sched, true));
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(1, out[1].wave);
}

test "two writers in sets ordered against each other are not ambiguous and run in the sets' order" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const early = try rig.addSet("early", &.{});
    const late = try rig.addSet("late", &.{early});
    const writes_one = [_]c.ke_id_access{idAccess(1, write)};
    var later = systemDesc("later", &probe, rig.phase);
    later.access = &writes_one;
    later.access_count = 1;
    later.sets = &.{late};
    later.set_count = 1;
    var sooner = later;
    sooner.name = "sooner";
    sooner.sets = &.{early};
    _ = try rig.add(later);
    _ = try rig.add(sooner);
    try R.check(rig.sched.build.?(rig.sched, true));
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(1, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "a set orders systems that touch nothing in common, through a set no system joins" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const first = try rig.addSet("first", &.{});
    const middle = try rig.addSet("middle", &.{first});
    const last = try rig.addSet("last", &.{middle});
    var b = systemDesc("b", &probe, rig.phase);
    b.sets = &.{last};
    b.set_count = 1;
    var a = systemDesc("a", &probe, rig.phase);
    a.sets = &.{first};
    a.set_count = 1;
    _ = try rig.add(b);
    _ = try rig.add(a);
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(1, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "a set may only follow a set of its own phase that already exists" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var id: c.ke_set_id = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(rig.sched, &.{ .name = "a", .phase = rig.phase, .after = &.{0}, .after_count = 1 }, &id));
    const other = try rig.addPhase("render");
    const foreign = try rig.addSet("foreign", &.{});
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(rig.sched, &.{ .name = "b", .phase = other, .after = &.{foreign}, .after_count = 1 }, &id));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(rig.sched, &.{ .name = "c", .phase = 9 }, &id));
}

test "an exclusive system runs alone before every other system of its phase" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(systemDesc("plain", &probe, rig.phase));
    var alone = systemDesc("alone", &probe, rig.phase);
    alone.exclusive = true;
    _ = try rig.add(alone);
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(1, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "queries requiring different members of one exclusive group do not conflict" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    try R.check(rig.sched.declare_exclusive.?(rig.sched, 10, 11));
    try R.check(rig.sched.declare_exclusive.?(rig.sched, 10, 12));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.declare_exclusive.?(rig.sched, 10, 10));
    var probe = Probe{};
    const left_terms = [_]c.ke_id_access{ idAccess(1, write), idAccess(11, read) };
    const right_terms = [_]c.ke_id_access{ idAccess(1, write), idAccess(12, read) };
    const left_query = [_]c.ke_query_desc{.{ .terms = &left_terms, .term_count = 2 }};
    const right_query = [_]c.ke_query_desc{.{ .terms = &right_terms, .term_count = 2 }};
    var left = systemDesc("left", &probe, rig.phase);
    left.queries = &left_query;
    left.query_count = 1;
    var right = systemDesc("right", &probe, rig.phase);
    right.queries = &right_query;
    right.query_count = 1;
    _ = try rig.add(left);
    _ = try rig.add(right);
    try R.check(rig.sched.build.?(rig.sched, true));
    var out: [2]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "a system writing only what lives within the phase and that nothing reads is culled, in cascade" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    try R.check(rig.sched.declare_lifetime.?(rig.sched, 1, c.KE_LIFETIME_PHASE));
    try R.check(rig.sched.declare_lifetime.?(rig.sched, 2, c.KE_LIFETIME_PHASE));
    var producer_probe = Probe{};
    var consumer_probe = Probe{};
    var kept_probe = Probe{};
    const produce = [_]c.ke_id_access{idAccess(1, write)};
    const consume = [_]c.ke_id_access{ idAccess(1, read), idAccess(2, write) };
    const keep = [_]c.ke_id_access{idAccess(3, write)};
    var producer = systemDesc("producer", &producer_probe, rig.phase);
    producer.access = &produce;
    producer.access_count = 1;
    var consumer = systemDesc("consumer", &consumer_probe, rig.phase);
    consumer.access = &consume;
    consumer.access_count = 2;
    var kept = systemDesc("kept", &kept_probe, rig.phase);
    kept.access = &keep;
    kept.access_count = 1;
    _ = try rig.add(producer);
    _ = try rig.add(consumer);
    _ = try rig.add(kept);
    var out: [3]c.ke_system_order = undefined;
    _ = try rig.describe(&out);
    try testing.expect(out[0].culled and out[1].culled and !out[2].culled);
    try rig.run();
    try testing.expectEqual(0, producer_probe.calls.load(.monotonic));
    try testing.expectEqual(0, consumer_probe.calls.load(.monotonic));
    try testing.expectEqual(1, kept_probe.calls.load(.monotonic));
}

test "declaring an id persistent again keeps its writers running" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    try R.check(rig.sched.declare_lifetime.?(rig.sched, 1, c.KE_LIFETIME_PHASE));
    var probe = Probe{};
    const produce = [_]c.ke_id_access{idAccess(1, write)};
    var producer = systemDesc("producer", &probe, rig.phase);
    producer.access = &produce;
    producer.access_count = 1;
    _ = try rig.add(producer);
    try R.check(rig.sched.declare_lifetime.?(rig.sched, 1, c.KE_LIFETIME_PERSISTENT));
    try rig.run();
    try testing.expectEqual(1, probe.calls.load(.monotonic));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.declare_lifetime.?(rig.sched, 1, 5));
}

test "a body that fails the run keeps the later waves from starting, while its own wave finishes" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var failing = Probe{};
    var beside = Probe{};
    var after = Probe{};
    const writes_one = [_]c.ke_id_access{idAccess(1, write)};
    const reads_one = [_]c.ke_id_access{idAccess(1, read)};
    var bad = systemDesc("bad", &failing, rig.phase);
    bad.execute = &refusing;
    bad.access = &writes_one;
    bad.access_count = 1;
    var reader = systemDesc("reader", &after, rig.phase);
    reader.access = &reads_one;
    reader.access_count = 1;
    _ = try rig.add(bad);
    _ = try rig.add(systemDesc("beside", &beside, rig.phase));
    _ = try rig.add(reader);
    try testing.expectEqual(R.code(error.Io), rig.sched.run.?(rig.sched, rig.phase, 0));
    try testing.expectEqual(1, beside.calls.load(.monotonic));
    try testing.expectEqual(0, after.calls.load(.monotonic));
}

const Registrar = struct {
    sched: *c.ke_scheduler,
    late: c.ke_system_desc,
    late_id: SystemId = 0,
    remove: SystemId = 0,
    remove_late: bool = false,
    nested: abi_result.c.ke_result = R.ok,
};

fn registering(_: ?*c.ke_scheduler_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const r: *Registrar = @ptrCast(@alignCast(ud.?));
    if (r.late_id == 0) {
        try_register: {
            R.check(r.sched.register_system.?(r.sched, &r.late, &r.late_id)) catch break :try_register;
            if (r.remove_late) _ = r.sched.unregister_system.?(r.sched, r.late_id);
        }
    }
    if (r.remove != 0) {
        _ = r.sched.unregister_system.?(r.sched, r.remove);
        r.remove = 0;
    }
    r.nested = r.sched.run.?(r.sched, 0, 0);
    return R.ok;
}

test "a system registered from a body runs from the next run on, and a run from a body is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var late = Probe{};
    var reg = Registrar{ .sched = rig.sched, .late = systemDesc("late", &late, rig.phase) };
    _ = try rig.add(.{ .name = "registrar", .phase = rig.phase, .user_data = &reg, .execute = &registering });
    try rig.run();
    try testing.expectEqual(0, late.calls.load(.monotonic));
    try testing.expectEqual(R.code(error.NotSupported), reg.nested);
    try rig.run();
    try testing.expectEqual(1, late.calls.load(.monotonic));
}

test "a system registered and unregistered by the same body never runs" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var late = Probe{};
    var reg = Registrar{ .sched = rig.sched, .late = systemDesc("late", &late, rig.phase), .remove_late = true };
    _ = try rig.add(.{ .name = "registrar", .phase = rig.phase, .user_data = &reg, .execute = &registering });
    try rig.run();
    try rig.run();
    try testing.expectEqual(0, late.calls.load(.monotonic));
}

test "a system unregistered from a body stops running from the next run" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var victim = Probe{};
    const victim_id = try rig.add(systemDesc("victim", &victim, rig.phase));
    var reg = Registrar{ .sched = rig.sched, .late = systemDesc("late", &victim, rig.phase), .late_id = 1, .remove = victim_id };
    _ = try rig.add(.{ .name = "registrar", .phase = rig.phase, .user_data = &reg, .execute = &registering });
    try rig.run();
    try testing.expectEqual(1, victim.calls.load(.monotonic));
    try rig.run();
    try testing.expectEqual(1, victim.calls.load(.monotonic));
}

test "an unregistered system no longer runs, and an id never issued is not found" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var gone = Probe{};
    var kept = Probe{};
    const id = try rig.add(systemDesc("gone", &gone, rig.phase));
    _ = try rig.add(systemDesc("kept", &kept, rig.phase));
    try R.check(rig.sched.unregister_system.?(rig.sched, id));
    try rig.run();
    try testing.expectEqual(0, gone.calls.load(.monotonic));
    try testing.expectEqual(1, kept.calls.load(.monotonic));
    try testing.expectEqual(R.code(error.NotFound), rig.sched.unregister_system.?(rig.sched, id));
    try testing.expectEqual(R.code(error.NotFound), rig.sched.unregister_system.?(rig.sched, 99));
}

fn spawning(ctx: ?*c.ke_scheduler_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const commands_of = ctx.?.commands.?;
    var entity: c.ke_entity = 0;
    try_record: {
        R.check(commands_of.spawn.?(commands_of, &entity)) catch break :try_record;
        const value: u32 = 7;
        R.check(commands_of.attach.?(commands_of, entity, 1, &value, @sizeOf(u32))) catch break :try_record;
    }
    return R.ok;
}

test "what a body records is applied after its wave, and what the caller records before the run" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    _ = try rig.add(.{ .name = "spawner", .phase = rig.phase, .execute = &spawning });
    const host = rig.sched.commands.?(rig.sched).?;
    try R.check(host.detach.?(host, 5, 1));
    try rig.run();
    try rig.ecs.received(.component_remove).times(1);
    try rig.ecs.received(.entity_reserve).times(1);
    try rig.ecs.received(.component_add).times(1);
    try zsub.inOrder(.{ rig.ecs.received(.component_remove), rig.ecs.received(.component_add) });
}

test "an attach whose size differs from the component's is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    const host = rig.sched.commands.?(rig.sched).?;
    const value: u64 = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), host.attach.?(host, 5, 1, &value, @sizeOf(u64)));
}

fn manySegments(args: std.meta.ArgsTuple(@typeInfo(@typeInfo(@FieldType(abi_ecs.c.ke_ecs, "query_resolve")).optional.child).pointer.child)) abi_result.c.ke_result {
    args[5].?.* = 6;
    return R.ok;
}

test "a query matching more segments than its buffer holds is resolved again into a bigger one and seen whole" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    _ = rig.ecs.when(.query_resolve).does(&manySegments);
    var probe = Probe{};
    const terms = [_]c.ke_id_access{idAccess(1, read)};
    const query = [_]c.ke_query_desc{.{ .terms = &terms, .term_count = 1 }};
    var desc = systemDesc("viewer", &probe, rig.phase);
    desc.queries = &query;
    desc.query_count = 1;
    _ = try rig.add(desc);
    try rig.run();
    try testing.expectEqual(6, probe.segments);
    try rig.ecs.received(.query_resolve).times(2);
    try rig.ecs.received(.query_register).times(1);
}

test "describing a phase reports the count, and refuses too small a capacity or an unknown phase" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(systemDesc("a", &probe, rig.phase));
    _ = try rig.add(systemDesc("b", &probe, rig.phase));
    var out: [1]c.ke_system_order = undefined;
    var count: u32 = 0;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.describe_phase.?(rig.sched, rig.phase, &out, 1, &count));
    try testing.expectEqual(2, count);
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.describe_phase.?(rig.sched, 5, &out, 1, &count));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.run.?(rig.sched, 5, 0));
}

test "creating a scheduler without an ecs, a task pool or a config is refused and leaves the handle zeroed" {
    var ecs: zsub.For(abi_ecs.c.ke_ecs) = undefined;
    try ecs.init();
    defer ecs.deinit();
    var pool: zsub.For(abi_task_pool.c.ke_task_pool) = undefined;
    try pool.init();
    defer pool.deinit();
    var handle: c.ke_scheduler_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(null, pool.api(), &.{ .reserved = 0 }, &handle));
    try testing.expectEqual(null, handle.ref);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(ecs.api(), null, &.{ .reserved = 0 }, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_scheduler_create(ecs.api(), pool.api(), null, &handle));
}

test "a slot given no scheduler refuses" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var id: c.ke_phase_id = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_phase.?(null, &.{ .name = "x" }, &id));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.run.?(null, 0, 0));
    try testing.expectEqual(null, rig.sched.commands.?(null));
}

test "nothing the scheduler allocated is left behind" {
    try heap.expectNoLeaks();
}
