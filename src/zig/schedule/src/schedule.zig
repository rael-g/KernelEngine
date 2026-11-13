//! The `ke_schedule` plugin: it orders the systems of one world by what they touch and the sets
//! they join, and runs them wave by wave across a task pool, over an ecs it borrows.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_schedule").logFn };

const abi_ecs = @import("abi_ecs");
const abi_result = @import("abi_result");
const abi_schedule = @import("abi_schedule");
const abi_completion = @import("abi_completion");
const abi_job = @import("abi_job");
const heap = @import("heap");
const order = @import("schedule_order.zig");
const body = @import("schedule_commands.zig");

const R = @import("result").Result(.{});
const log = std.log.scoped(.schedule);

const c = abi_schedule.c;
const gpa = heap.gpa;
const Id = c.ke_component_id;
const Term = abi_ecs.c.ke_ecs_query_term;
const SetId = c.ke_schedule_set_id;
const SystemId = c.ke_schedule_system_id;

/// One query of a system: its own copy of the description and the ecs query it was registered as.
const Query = struct {
    shape: order.Query,
    track_changes: bool,
    id: abi_ecs.c.ke_query_id = abi_ecs.c.KE_QUERY_INVALID,
    bound: bool = false,
};

/// A system as the schedule holds it: its own copy of what was registered, in `arena`, the access
/// the conflict rule reads, which merges its query terms with `explicit`, and the segments its
/// queries resolve to. It is linked through `next` while it waits on `State.pending`; `runs` is what
/// its condition answered for the current run.
const System = struct {
    arena: std.heap.ArenaAllocator,
    id: SystemId,
    name: [:0]const u8,
    user_data: ?*anyopaque,
    execute: c.ke_schedule_execute_fn,
    condition: c.ke_schedule_condition_fn,
    per_entity: bool,
    exclusive: bool,
    access: []const Term,
    explicit: []const Term,
    queries: []Query,
    shapes: []const order.Query,
    segments: []body.Segments,
    views: []body.View,
    sets: []const SetId,
    runs: bool = true,
    next: ?*System = null,

    fn destroy(s: *System) void {
        for (s.segments) |*seg| seg.deinit();
        s.arena.deinit();
        gpa.destroy(s);
    }
};

/// The order last built, kept until a registration changes: the systems in registration order, and
/// `waves` and `ambiguous` beside them.
const Built = struct {
    valid: bool = false,
    systems: []*System = &.{},
    waves: []u32 = &.{},
    ambiguous: []bool = &.{},
    wave_count: u32 = 0,
    failure: order.Problem = .none,
    ambiguity: order.Problem = .none,

    fn clear(b: *Built) void {
        gpa.free(b.systems);
        gpa.free(b.waves);
        gpa.free(b.ambiguous);
        b.* = .{};
    }
};

const Set = struct {
    name: [:0]u8,
    after: []SetId,
};

const Removal = struct { id: SystemId, next: ?*Removal = null };

/// One job of a wave: one slice of one system, with its own context and queue. The job system is
/// handed its address, so it stays in place until the wave has been waited for.
const Package = struct {
    context: body.Context,
    queue: body.Queue = .{},
    system: *System,
    dt: f32,
    job: ?*abi_completion.c.ke_completion = null,
};

threadlocal var inside_body: bool = false;

/// The state behind the `ke_schedule` handle, whose `api.handle` points back at it. Sets and systems
/// change only while no run is in flight: a system registered or removed from a body, or while a
/// run is in flight, waits on the lock-free `pending` and `removals` lists until the next run
/// applies them, in call order, and every other change is refused then. `in_flight` holds from the
/// start of a run until its driver job, which runs the waves with `dt`, ends.
const State = struct {
    api: c.ke_schedule,
    ecs: *abi_ecs.c.ke_ecs,
    jobs: *abi_job.c.ke_job_system,
    refuse_ambiguity: bool,
    in_flight: std.atomic.Value(bool) = .init(false),
    dt: f32 = 0,
    built: Built = .{},
    sets: std.ArrayList(Set) = .empty,
    systems: std.ArrayList(*System) = .empty,
    packages: std.ArrayList(Package) = .empty,
    next_system: std.atomic.Value(SystemId) = .init(0),
    pending: std.atomic.Value(?*System) = .init(null),
    removals: std.atomic.Value(?*Removal) = .init(null),
    host_queue: body.Queue = .{},
    host: body.Context,

    fn dirty(s: *State) void {
        s.built.clear();
    }
};

fn stateOf(self: ?*c.ke_schedule) ?*State {
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

fn refuseInBody() R.Error!void {
    if (inside_body) return reject(error.NotSupported, "the call is refused from a body");
}

fn deferred(s: *State) bool {
    return inside_body or s.in_flight.load(.acquire);
}

/// Slot `register_set`.
fn registerSet(self: ?*c.ke_schedule, desc: ?*const c.ke_schedule_set_desc, out_id: ?*SetId) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("register_set", error.InvalidArgument);
    const out = out_id orelse return failed("register_set", error.InvalidArgument);
    out.* = addSet(s, desc orelse return failed("register_set", error.InvalidArgument)) catch |err| return failed("register_set", err);
    return R.ok;
}

fn addSet(s: *State, desc: *const c.ke_schedule_set_desc) R.Error!SetId {
    if (deferred(s)) return reject(error.NotSupported, "a set is refused from a body or while a run is in flight");
    const name = desc.name orelse return reject(error.InvalidArgument, "a set needs a name");
    const after: []const SetId = if (desc.after_count == 0) &.{} else (desc.after orelse return reject(error.InvalidArgument, "a set counts sets it does not point at"))[0..desc.after_count];
    for (after) |a| {
        if (a >= s.sets.items.len) return reject(error.InvalidArgument, "a set follows an unknown set");
    }
    const copy = try gpa.dupeZ(u8, std.mem.span(name));
    errdefer gpa.free(copy);
    const after_copy = try gpa.dupe(SetId, after);
    errdefer gpa.free(after_copy);
    try s.sets.append(gpa, .{ .name = copy, .after = after_copy });
    s.dirty();
    return @intCast(s.sets.items.len - 1);
}

fn validAccess(list: []const Term) bool {
    const known: c_uint = abi_ecs.c.KE_ECS_ACCESS_READ | abi_ecs.c.KE_ECS_ACCESS_WRITE;
    for (list) |a| {
        const bits: c_uint = @intCast(a.access);
        if (bits == 0 or (bits & ~known) != 0) return false;
    }
    return true;
}

fn merge(list: *std.ArrayList(Term), a: std.mem.Allocator, want: Term) !void {
    for (list.items) |*have| {
        if (have.component == want.component) {
            have.access = @intCast(@as(c_uint, @intCast(have.access)) | @as(c_uint, @intCast(want.access)));
            return;
        }
    }
    try list.append(a, want);
}

fn ids(ptr: ?[*]const Id, count: u32) R.Error![]const Id {
    if (count == 0) return &.{};
    return (ptr orelse return reject(error.InvalidArgument, "a query counts filters it does not point at"))[0..count];
}

/// Copies a registration into a new system that owns everything it was given.
fn makeSystem(s: *State, desc: *const c.ke_schedule_system_desc) R.Error!*System {
    if (desc.execute == null) return reject(error.InvalidArgument, "a system needs a body");
    const name = desc.name orelse return reject(error.InvalidArgument, "a system needs a name");
    const queries: []const abi_ecs.c.ke_ecs_query_desc = if (desc.query_count == 0) &.{} else (desc.queries orelse return reject(error.InvalidArgument, "a system counts queries it does not point at"))[0..desc.query_count];
    const explicit: []const Term = if (desc.access_count == 0) &.{} else (desc.access orelse return reject(error.InvalidArgument, "a system counts access it does not point at"))[0..desc.access_count];
    const sets: []const SetId = if (desc.set_count == 0) &.{} else (desc.sets orelse return reject(error.InvalidArgument, "a system counts sets it does not point at"))[0..desc.set_count];
    for (queries) |q| {
        if (q.term_count == 0 or q.terms == null) return reject(error.InvalidArgument, "a query declares no terms");
        if (!validAccess(q.terms.?[0..q.term_count])) return reject(error.InvalidArgument, "a query term has no known access");
        _ = try ids(q.with, q.with_count);
        _ = try ids(q.without, q.without_count);
    }
    if (!validAccess(explicit)) return reject(error.InvalidArgument, "an access entry has no known access");
    if (sets.len == 0) return reject(error.InvalidArgument, "a system joins no set");
    for (sets) |set| {
        if (set >= s.sets.items.len) return reject(error.InvalidArgument, "a system joins an unknown set");
    }

    const system = try gpa.create(System);
    errdefer gpa.destroy(system);
    system.arena = .init(gpa);
    errdefer system.arena.deinit();
    const a = system.arena.allocator();

    const owned_queries = try a.alloc(Query, queries.len);
    const shapes = try a.alloc(order.Query, queries.len);
    var access: std.ArrayList(Term) = .empty;
    for (queries, owned_queries, shapes) |q, *owned, *shape| {
        shape.* = .{
            .terms = try a.dupe(Term, q.terms.?[0..q.term_count]),
            .with = try a.dupe(Id, try ids(q.with, q.with_count)),
            .without = try a.dupe(Id, try ids(q.without, q.without_count)),
        };
        owned.* = .{ .shape = shape.*, .track_changes = q.track_changes };
        for (shape.terms) |t| try merge(&access, a, t);
    }
    for (explicit) |e| try merge(&access, a, e);
    const segments = try a.alloc(body.Segments, queries.len);
    @memset(segments, .{});
    const views = try a.alloc(body.View, queries.len);
    @memset(views, .{});

    system.* = .{
        .arena = system.arena,
        .id = 0,
        .name = try a.dupeZ(u8, std.mem.span(name)),
        .user_data = desc.user_data,
        .execute = desc.execute,
        .condition = desc.condition,
        .per_entity = desc.per_entity,
        .exclusive = desc.exclusive,
        .access = access.items,
        .explicit = try a.dupe(Term, explicit),
        .queries = owned_queries,
        .shapes = shapes,
        .segments = segments,
        .views = views,
        .sets = try a.dupe(SetId, sets),
    };
    return system;
}

/// Slot `register_system`. From a body, the system waits on `State.pending` for the next run.
fn registerSystem(self: ?*c.ke_schedule, desc: ?*const c.ke_schedule_system_desc, out_id: ?*SystemId) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("register_system", error.InvalidArgument);
    const out = out_id orelse return failed("register_system", error.InvalidArgument);
    out.* = addSystem(s, desc orelse return failed("register_system", error.InvalidArgument)) catch |err| return failed("register_system", err);
    return R.ok;
}

fn addSystem(s: *State, desc: *const c.ke_schedule_system_desc) R.Error!SystemId {
    const system = try makeSystem(s, desc);
    system.id = s.next_system.fetchAdd(1, .monotonic) + 1;
    if (deferred(s)) {
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
    s.dirty();
    return system.id;
}

/// Slot `unregister_system`. From a body, the removal waits on `State.removals` for the next run,
/// where an id already removed is dropped without a failure.
fn unregisterSystem(self: ?*c.ke_schedule, id: SystemId) callconv(.c) abi_result.c.ke_result {
    const s = stateOf(self) orelse return failed("unregister_system", error.InvalidArgument);
    removeSystem(s, id) catch |err| return failed("unregister_system", err);
    return R.ok;
}

fn removeSystem(s: *State, id: SystemId) R.Error!void {
    if (id == 0 or id > s.next_system.load(.monotonic)) return reject(error.NotFound, "no system has that id");
    if (deferred(s)) {
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
        s.dirty();
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
        s.dirty();
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

/// Builds the order when a registration changed since the last build. A cycle is kept as the
/// order's failure, which `run` and `describe` report until a registration changes.
fn buildOrder(s: *State) R.Error!void {
    if (s.built.valid) return;
    s.built.clear();

    const set_count = s.sets.items.len;
    const after = try gpa.alloc([]const u32, set_count);
    defer gpa.free(after);
    for (s.sets.items, after) |set, *list| list.* = set.after;
    const follows = try gpa.alloc(bool, set_count * set_count);
    defer gpa.free(follows);
    const cycle = order.closeSets(after, follows);

    const systems = try gpa.dupe(*System, s.systems.items);
    errdefer gpa.free(systems);
    const nodes = try gpa.alloc(order.Node, systems.len);
    defer gpa.free(nodes);
    for (systems, nodes) |system, *node| {
        node.* = .{
            .name = system.name,
            .exclusive = system.exclusive,
            .access = system.access,
            .explicit = system.explicit,
            .queries = system.shapes,
            .sets = system.sets,
        };
    }

    const waves = try gpa.alloc(u32, nodes.len);
    errdefer gpa.free(waves);
    const ambiguous = try gpa.alloc(bool, nodes.len);
    errdefer gpa.free(ambiguous);
    @memset(ambiguous, false);
    const built: order.Order = if (cycle) |set| .{ .failure = .{ .cycle = s.sets.items[set].name } } else order.order(nodes, follows, set_count, &.{}, waves, ambiguous);
    if (built.failure == .out_of_memory) return error.OutOfMemory;

    s.built = .{
        .valid = true,
        .systems = systems,
        .waves = waves,
        .ambiguous = ambiguous,
        .wave_count = built.wave_count,
        .failure = built.failure,
        .ambiguity = built.ambiguity,
    };
    switch (built.ambiguity) {
        .ambiguity => |a| log.info("{s} and {s} both write {d} with no order between them; either may run first", .{ a.first, a.second, a.id }),
        else => {},
    }
}

/// The failure the order holds, logged with the names involved.
fn orderFailure(built: *const Built, refuse_ambiguity: bool) R.Error!void {
    switch (built.failure) {
        .none, .out_of_memory, .ambiguity => {},
        .cycle => |name| {
            log.warn("the order has a cycle through {s}", .{name});
            return error.General;
        },
    }
    if (!refuse_ambiguity) return;
    switch (built.ambiguity) {
        .ambiguity => |a| {
            log.warn("{s} and {s} both write {d} with no order between them", .{ a.first, a.second, a.id });
            return error.General;
        },
        else => {},
    }
}

fn bindQueries(s: *State) R.Error!void {
    for (s.systems.items) |system| {
        for (system.queries) |*q| {
            if (q.bound) continue;
            const register = s.ecs.query_register orelse return reject(error.NotSupported, "the ecs registers no query");
            const desc: abi_ecs.c.ke_ecs_query_desc = .{
                .terms = @ptrCast(q.shape.terms.ptr),
                .term_count = @intCast(q.shape.terms.len),
                .with = q.shape.with.ptr,
                .with_count = @intCast(q.shape.with.len),
                .without = q.shape.without.ptr,
                .without_count = @intCast(q.shape.without.len),
                .track_changes = q.track_changes,
            };
            R.check(register(s.ecs, &desc, &q.id)) catch |err| {
                log.warn("the ecs refused a query of {s}", .{system.name});
                return err;
            };
            q.bound = true;
        }
    }
}

fn slicesOf(s: *State, system: *const System) u32 {
    if (!system.per_entity or system.exclusive) return 1;
    return @max(s.jobs.worker_slots.?(s.jobs), 1);
}

/// The job body of one package.
fn runPackage(data: ?*anyopaque, _: ?*const abi_job.c.ke_job_ctx) callconv(.c) abi_result.c.ke_result {
    const pkg: *Package = @ptrCast(@alignCast(data.?));
    inside_body = true;
    defer inside_body = false;
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

/// Slot `run`. Applies the pending registrations and the caller's commands and builds the order on
/// the calling thread, then hands the waves to a driver job, whose completion is the run's.
fn run(self: ?*c.ke_schedule, dt: f32, out_completion: ?*?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
    const out = out_completion orelse return failed("run", error.InvalidArgument);
    out.* = null;
    const s = stateOf(self) orelse return failed("run", error.InvalidArgument);
    startRun(s, dt, out) catch |err| return failed("run", err);
    return R.ok;
}

fn startRun(s: *State, dt: f32, out: *?*abi_completion.c.ke_completion) R.Error!void {
    try refuseInBody();
    if (!(dt >= 0)) return reject(error.InvalidArgument, "a run needs a dt of zero or more");
    if (s.in_flight.load(.acquire)) return reject(error.NotSupported, "a run is refused while another is in flight");
    applyPending(s);
    s.host_queue.flush(s.ecs) catch |err| {
        log.warn("applying the caller's commands failed", .{});
        return err;
    };
    try bindQueries(s);
    try buildOrder(s);
    try orderFailure(&s.built, s.refuse_ambiguity);
    s.dt = dt;
    s.in_flight.store(true, .release);
    R.check(s.jobs.dispatch.?(s.jobs, "schedule run", &drive, s, null, 0, out)) catch |err| {
        s.in_flight.store(false, .release);
        return err;
    };
}

/// The driver job of a run: runs the waves, ending the run with the first failure.
fn drive(data: ?*anyopaque, _: ?*const abi_job.c.ke_job_ctx) callconv(.c) abi_result.c.ke_result {
    const s: *State = @ptrCast(@alignCast(data.?));
    defer s.in_flight.store(false, .release);
    if (runWaves(s, s.dt)) |f| {
        log.warn("{s} failed: {t}", .{ f.name, f.err });
        return R.code(f.err);
    }
    return R.ok;
}

/// Asks the condition of every system of wave `w` and resolves the queries of those that run, once
/// every earlier wave finished and what it recorded was applied.
fn prepare(s: *State, w: usize) R.Error!void {
    for (s.built.systems, s.built.waves) |system, wave| {
        if (wave != w) continue;
        system.runs = true;
        if (system.condition) |cond| {
            R.check(cond(system.user_data, &system.runs)) catch |err| {
                log.warn("the condition of {s} failed", .{system.name});
                return err;
            };
        }
        if (!system.runs) continue;
        for (system.queries, system.segments, system.views) |q, *seg, *v| {
            seg.resolve(s.ecs, q.id, q.shape.terms.len) catch |err| {
                log.warn("resolving a query of {s} failed", .{system.name});
                return err;
            };
            v.* = .of(seg);
        }
    }
}

/// Runs the built waves with the views the systems hold, and returns the first failure.
fn runWaves(s: *State, dt: f32) ?Failure {
    const built = &s.built;
    var failure: ?Failure = null;
    for (0..built.wave_count) |w| {
        prepare(s, w) catch |err| return .{ .err = err, .name = "a condition or a query" };
        var count: usize = 0;
        for (built.systems, built.waves) |system, wave| {
            if (wave == w and system.runs) count += slicesOf(s, system);
        }
        s.packages.clearRetainingCapacity();
        s.packages.ensureTotalCapacity(gpa, count) catch return .{ .err = error.OutOfMemory, .name = "the run" };
        for (built.systems, built.waves) |system, wave| {
            if (wave != w or !system.runs) continue;
            const slices = slicesOf(s, system);
            for (0..slices) |index| {
                s.packages.appendAssumeCapacity(.{
                    .context = .{ .ecs = s.ecs, .queue = null, .views = system.views, .slice_index = @intCast(index), .slice_count = slices },
                    .system = system,
                    .dt = dt,
                });
            }
        }
        for (s.packages.items) |*pkg| {
            pkg.context.queue = &pkg.queue;
            pkg.context.bind();
        }
        for (s.packages.items) |*pkg| keepFirst(&failure, s.jobs.dispatch.?(s.jobs, pkg.system.name.ptr, &runPackage, pkg, null, 0, &pkg.job), pkg.system.name);
        for (s.packages.items) |*pkg| {
            const job = pkg.job orelse continue;
            keepFirst(&failure, job.wait.?(job), pkg.system.name);
            job.release.?(job);
            pkg.job = null;
        }
        for (s.packages.items) |*pkg| {
            pkg.queue.flush(s.ecs) catch |err| {
                if (failure == null) failure = .{ .err = err, .name = pkg.system.name };
            };
            pkg.queue.deinit();
        }
        if (failure != null) break;
    }
    return failure;
}

/// Slot `commands`.
fn commands(self: ?*c.ke_schedule) callconv(.c) ?*abi_ecs.c.ke_ecs_commands {
    const s = stateOf(self) orelse return null;
    return @ptrCast(&s.host.commands);
}

/// Slot `reads`. Walks the registered systems, which change only while no run is in flight.
fn reads(self: ?*c.ke_schedule, component: Id) callconv(.c) bool {
    const s = stateOf(self) orelse return false;
    for (s.systems.items) |system| {
        for (system.access) |a| {
            if (a.component == component and (@as(c_uint, @intCast(a.access)) & abi_ecs.c.KE_ECS_ACCESS_READ) != 0) return true;
        }
    }
    return false;
}

/// Slot `destroy` of the handle: frees every system, pending or registered, and every declaration.
fn destroy(self: ?*c.ke_schedule) callconv(.c) void {
    const s = stateOf(self) orelse return;
    applyPending(s);
    for (s.systems.items) |system| system.destroy();
    s.systems.deinit(gpa);
    s.built.clear();
    for (s.sets.items) |set| {
        gpa.free(set.name);
        gpa.free(set.after);
    }
    s.sets.deinit(gpa);
    s.packages.deinit(gpa);
    s.host_queue.deinit();
    gpa.destroy(s);
}

/// The factory: a schedule over an ecs and a job system it borrows and never frees.
export fn ke_schedule_create(ecs: ?*abi_ecs.c.ke_ecs, job_system: ?*abi_job.c.ke_job_system, config: ?*const c.ke_schedule_config, out_schedule: ?*c.ke_schedule_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_schedule orelse return failed("ke_schedule_create", error.InvalidArgument);
    out.* = .{};
    if (ecs == null or job_system == null or config == null) return failed("ke_schedule_create", reject(error.InvalidArgument, "a schedule needs an ecs, a job system and its config"));
    const s = gpa.create(State) catch |err| return failed("ke_schedule_create", err);
    s.* = .{
        .api = .{
            .register_set = &registerSet,
            .register_system = &registerSystem,
            .unregister_system = &unregisterSystem,
            .run = &run,
            .commands = &commands,
            .reads = &reads,
        },
        .ecs = ecs.?,
        .jobs = job_system.?,
        .refuse_ambiguity = config.?.refuse_ambiguity,
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

const Done = struct {
    api: abi_completion.c.ke_completion,
    result: abi_result.c.ke_result,

    fn poll(c_in: ?*abi_completion.c.ke_completion, out: ?*abi_result.c.ke_result) callconv(.c) bool {
        const d: *Done = @ptrCast(@alignCast(c_in.?.handle));
        if (out) |o| o.* = d.result;
        return true;
    }

    fn wait(c_in: ?*abi_completion.c.ke_completion) callconv(.c) abi_result.c.ke_result {
        return @as(*Done, @ptrCast(@alignCast(c_in.?.handle))).result;
    }

    fn release(c_in: ?*abi_completion.c.ke_completion) callconv(.c) void {
        gpa.destroy(@as(*Done, @ptrCast(@alignCast(c_in.?.handle))));
    }
};

fn inlineDispatch(args: std.meta.ArgsTuple(@typeInfo(@typeInfo(@FieldType(abi_job.c.ke_job_system, "dispatch")).optional.child).pointer.child)) abi_result.c.ke_result {
    const ctx: abi_job.c.ke_job_ctx = .{ .dep_results = null, .dep_count = 0 };
    const result = args[2].?(args[3], &ctx);
    const done = gpa.create(Done) catch return R.code(error.OutOfMemory);
    done.* = .{ .api = .{ .handle = done, .poll = &Done.poll, .wait = &Done.wait, .release = &Done.release }, .result = result };
    args[6].?.* = &done.api;
    return R.ok;
}

fn runOnce(sched: *c.ke_schedule, dt: f32) abi_result.c.ke_result {
    var done: ?*abi_completion.c.ke_completion = null;
    const started = sched.run.?(sched, dt, &done);
    if (started != R.ok) return started;
    const result = done.?.wait.?(done.?);
    done.?.release.?(done.?);
    return result;
}

const Placed = struct { id: SystemId, wave: u32, ambiguous: bool };

const Rig = struct {
    ecs: zsub.For(abi_ecs.c.ke_ecs),
    jobs: zsub.For(abi_job.c.ke_job_system),
    handle: c.ke_schedule_handle,
    sched: *c.ke_schedule,
    set: [1]SetId,

    fn init(self: *Rig, workers: u32) !void {
        try self.ecs.init();
        _ = self.ecs.when(.query_register).writesFresh(2);
        _ = self.ecs.when(.entity_reserve).writesFresh(1);
        _ = self.ecs.when(.component_size).returns(4);
        try self.jobs.init();
        _ = self.jobs.when(.dispatch).does(&inlineDispatch);
        _ = self.jobs.when(.worker_slots).returns(workers);
        try R.check(ke_schedule_create(self.ecs.api(), self.jobs.api(), &.{ .refuse_ambiguity = false }, &self.handle));
        self.sched = self.handle.ref.?;
        self.set = .{try self.addSet("update", &.{})};
    }

    fn deinit(self: *Rig) void {
        self.handle.destroy.?(self.sched);
        self.jobs.deinit();
        self.ecs.deinit();
    }

    fn addSet(self: *Rig, name: [*:0]const u8, after: []const SetId) !SetId {
        var id: SetId = undefined;
        try R.check(self.sched.register_set.?(self.sched, &.{ .name = name, .after = after.ptr, .after_count = @intCast(after.len) }, &id));
        return id;
    }

    fn desc(self: *Rig, name: [*:0]const u8, probe: *Probe) c.ke_schedule_system_desc {
        return .{ .name = name, .user_data = probe, .execute = &counting, .sets = &self.set, .set_count = 1 };
    }

    fn add(self: *Rig, d: c.ke_schedule_system_desc) !SystemId {
        var id: SystemId = undefined;
        try R.check(self.sched.register_system.?(self.sched, &d, &id));
        return id;
    }

    fn run(self: *Rig) !void {
        try R.check(runOnce(self.sched, 0));
    }

    fn build(self: *Rig, refuse_ambiguity: bool) R.Error!void {
        const st = stateOf(self.sched).?;
        try buildOrder(st);
        try orderFailure(&st.built, refuse_ambiguity);
    }

    fn describe(self: *Rig, out: []Placed) !u32 {
        try self.build(false);
        const built = &stateOf(self.sched).?.built;
        for (built.systems, built.waves, built.ambiguous, out[0..built.systems.len]) |system, wave, ambiguous, *entry| {
            entry.* = .{ .id = system.id, .wave = wave, .ambiguous = ambiguous };
        }
        return @intCast(built.systems.len);
    }
};

const Probe = struct {
    calls: std.atomic.Value(u32) = .init(0),
    slices: [8]std.atomic.Value(u32) = @splat(.init(0)),
    seen_count: u32 = 0,
    segments: usize = 0,
    allow: bool = true,
};

fn counting(ctx: ?*c.ke_schedule_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
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

fn refusing(_: ?*c.ke_schedule_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
    const probe: *Probe = @ptrCast(@alignCast(ud.?));
    _ = probe.calls.fetchAdd(1, .monotonic);
    return R.code(error.Io);
}

fn allowed(ud: ?*anyopaque, out_runs: ?*bool) callconv(.c) abi_result.c.ke_result {
    const probe: *Probe = @ptrCast(@alignCast(ud.?));
    out_runs.?.* = probe.allow;
    return R.ok;
}

fn broken(_: ?*anyopaque, _: ?*bool) callconv(.c) abi_result.c.ke_result {
    return R.code(error.Io);
}

fn term(id: Id, mode: c_uint) Term {
    return .{ .component = id, .access = @intCast(mode) };
}

fn queryOf(terms: []const Term, with: []const Id, without: []const Id) abi_ecs.c.ke_ecs_query_desc {
    return .{ .terms = terms.ptr, .term_count = @intCast(terms.len), .with = with.ptr, .with_count = @intCast(with.len), .without = without.ptr, .without_count = @intCast(without.len), .track_changes = false };
}

const read = abi_ecs.c.KE_ECS_ACCESS_READ;
const write = abi_ecs.c.KE_ECS_ACCESS_WRITE;

test "a schedule with no system runs and tears down" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    try rig.run();
}

test "a system runs once per run" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(rig.desc("here", &probe));
    try rig.run();
    try rig.run();
    try testing.expectEqual(2, probe.calls.load(.monotonic));
}

test "a system whose condition answers false skips that run, asked again at every run" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{ .allow = false };
    var desc = rig.desc("guarded", &probe);
    desc.condition = &allowed;
    _ = try rig.add(desc);
    try rig.run();
    try testing.expectEqual(0, probe.calls.load(.monotonic));
    probe.allow = true;
    try rig.run();
    try testing.expectEqual(1, probe.calls.load(.monotonic));
}

test "a condition that fails fails the run before any body runs" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var plain = Probe{};
    _ = try rig.add(rig.desc("plain", &plain));
    var probe = Probe{};
    var desc = rig.desc("guarded", &probe);
    desc.condition = &broken;
    _ = try rig.add(desc);
    try testing.expectEqual(R.code(error.Io), runOnce(rig.sched, 0));
    try testing.expectEqual(0, plain.calls.load(.monotonic));
}

test "a system that does not promise per-entity work runs as one slice" {
    var rig: Rig = undefined;
    try rig.init(4);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(rig.desc("whole", &probe));
    try rig.run();
    try testing.expectEqual(1, probe.calls.load(.monotonic));
    try testing.expectEqual(1, probe.seen_count);
}

test "a per-entity system runs every slice of its set exactly once, one per worker" {
    var rig: Rig = undefined;
    try rig.init(4);
    defer rig.deinit();
    var probe = Probe{};
    var desc = rig.desc("sliced", &probe);
    desc.per_entity = true;
    _ = try rig.add(desc);
    try rig.run();
    try testing.expectEqual(4, probe.calls.load(.monotonic));
    for (probe.slices[0..4]) |slice| try testing.expectEqual(1, slice.load(.monotonic));
}

test "a system with no body, no name, no set or an unknown set is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    var no_body = rig.desc("x", &probe);
    no_body.execute = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &no_body, &id));
    var no_name = rig.desc("x", &probe);
    no_name.name = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &no_name, &id));
    var no_set = rig.desc("x", &probe);
    no_set.set_count = 0;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &no_set, &id));
    var unknown = rig.desc("x", &probe);
    unknown.sets = &.{7};
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &unknown, &id));
}

test "a query declaring no terms, or counting terms or filters it does not point at, is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    const empty = [_]abi_ecs.c.ke_ecs_query_desc{queryOf(&.{}, &.{}, &.{})};
    var desc = rig.desc("x", &probe);
    desc.queries = &empty;
    desc.query_count = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
    desc.queries = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
    const terms = [_]Term{term(1, read)};
    var dangling = [_]abi_ecs.c.ke_ecs_query_desc{queryOf(&terms, &.{}, &.{})};
    dangling[0].with = null;
    dangling[0].with_count = 1;
    desc.queries = &dangling;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
}

test "an access with no known mode is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var id: SystemId = undefined;
    const list = [_]Term{term(1, 0)};
    var desc = rig.desc("x", &probe);
    desc.access = &list;
    desc.access_count = 1;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
    const unknown = [_]Term{term(1, 8)};
    desc.access = &unknown;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_system.?(rig.sched, &desc, &id));
}

test "a registered system keeps its own copy of the name and the access it was given" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    var name = "writer".*;
    var list = [_]Term{term(1, write)};
    var desc = rig.desc(&name, &probe);
    desc.access = &list;
    desc.access_count = 1;
    _ = try rig.add(desc);
    @memset(&name, 'x');
    list[0] = term(9, read);
    var reader = rig.desc("reader", &probe);
    const reads_one = [_]Term{term(1, read)};
    reader.access = &reads_one;
    reader.access_count = 1;
    _ = try rig.add(reader);
    var out: [2]Placed = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(1, out[1].wave);
}

test "a writer of a component runs in a wave before a system that only reads it, and disjoint systems share a wave" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const reads_one = [_]Term{term(1, read)};
    const writes_one = [_]Term{term(1, write)};
    const writes_two = [_]Term{term(2, write)};
    var reader = rig.desc("reader", &probe);
    reader.access = &reads_one;
    reader.access_count = 1;
    var writer = rig.desc("writer", &probe);
    writer.access = &writes_one;
    writer.access_count = 1;
    var other = rig.desc("other", &probe);
    other.access = &writes_two;
    other.access_count = 1;
    const r = try rig.add(reader);
    const w = try rig.add(writer);
    const o = try rig.add(other);
    var out: [3]Placed = undefined;
    try testing.expectEqual(3, try rig.describe(&out));
    try testing.expectEqual(Placed{ .id = r, .wave = 1, .ambiguous = false }, out[0]);
    try testing.expectEqual(Placed{ .id = w, .wave = 0, .ambiguous = false }, out[1]);
    try testing.expectEqual(Placed{ .id = o, .wave = 0, .ambiguous = false }, out[2]);
}

test "two writers with no other order run in registration order, are described as ambiguous, and a build refusing ambiguity fails" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const writes_one = [_]Term{term(1, write)};
    var first = rig.desc("first", &probe);
    first.access = &writes_one;
    first.access_count = 1;
    var second = first;
    second.name = "second";
    _ = try rig.add(first);
    _ = try rig.add(second);
    _ = try rig.add(rig.desc("bystander", &probe));
    try rig.build(false);
    try testing.expectError(error.General, rig.build(true));
    var out: [3]Placed = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(1, out[1].wave);
    try testing.expect(out[0].ambiguous and out[1].ambiguous and !out[2].ambiguous);
}

test "two writers in sets ordered against each other are not ambiguous and run in the sets' order" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const early = try rig.addSet("early", &.{});
    const late = try rig.addSet("late", &.{early});
    const writes_one = [_]Term{term(1, write)};
    var later = rig.desc("later", &probe);
    later.access = &writes_one;
    later.access_count = 1;
    later.sets = &.{late};
    later.set_count = 1;
    var sooner = later;
    sooner.name = "sooner";
    sooner.sets = &.{early};
    _ = try rig.add(later);
    _ = try rig.add(sooner);
    try rig.build(true);
    var out: [2]Placed = undefined;
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
    var b = rig.desc("b", &probe);
    b.sets = &.{last};
    b.set_count = 1;
    var a = rig.desc("a", &probe);
    a.sets = &.{first};
    a.set_count = 1;
    _ = try rig.add(b);
    _ = try rig.add(a);
    var out: [2]Placed = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(1, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "a set may only follow a set that already exists, and a set with no name is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var id: SetId = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(rig.sched, &.{ .name = "a", .after = &.{9}, .after_count = 1 }, &id));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(rig.sched, &.{ .name = null }, &id));
}

test "an exclusive system runs alone before every other system" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    _ = try rig.add(rig.desc("plain", &probe));
    var alone = rig.desc("alone", &probe);
    alone.exclusive = true;
    _ = try rig.add(alone);
    var out: [2]Placed = undefined;
    _ = try rig.describe(&out);
    try testing.expectEqual(1, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

fn twoWriters(rig: *Rig, probe: *Probe, left: *const [1]abi_ecs.c.ke_ecs_query_desc, right: *const [1]abi_ecs.c.ke_ecs_query_desc) ![2]Placed {
    var a = rig.desc("left", probe);
    a.queries = left;
    a.query_count = 1;
    var b = rig.desc("right", probe);
    b.queries = right;
    b.query_count = 1;
    _ = try rig.add(a);
    _ = try rig.add(b);
    try rig.build(true);
    var out: [2]Placed = undefined;
    _ = try rig.describe(&out);
    return out;
}

test "a query excluding a component the other requires does not conflict with it" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const writes_one = [_]Term{term(1, write)};
    const marker = [_]Id{20};
    const out = try twoWriters(&rig, &probe, &.{queryOf(&writes_one, &marker, &.{})}, &.{queryOf(&writes_one, &.{}, &marker)});
    try testing.expectEqual(0, out[0].wave);
    try testing.expectEqual(0, out[1].wave);
}

test "queries whose filters overlap still conflict" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const writes_one = [_]Term{term(1, write)};
    try testing.expectError(error.General, twoWriters(&rig, &probe, &.{queryOf(&writes_one, &.{20}, &.{})}, &.{queryOf(&writes_one, &.{}, &.{21})}));
}

test "a body that fails the run keeps the later waves from starting, while its own wave finishes" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var failing = Probe{};
    var beside = Probe{};
    var after = Probe{};
    const writes_one = [_]Term{term(1, write)};
    const reads_one = [_]Term{term(1, read)};
    var bad = rig.desc("bad", &failing);
    bad.execute = &refusing;
    bad.access = &writes_one;
    bad.access_count = 1;
    var reader = rig.desc("reader", &after);
    reader.access = &reads_one;
    reader.access_count = 1;
    _ = try rig.add(bad);
    _ = try rig.add(rig.desc("beside", &beside));
    _ = try rig.add(reader);
    try testing.expectEqual(R.code(error.Io), runOnce(rig.sched, 0));
    try testing.expectEqual(1, beside.calls.load(.monotonic));
    try testing.expectEqual(0, after.calls.load(.monotonic));
}

const Registrar = struct {
    sched: *c.ke_schedule,
    late: c.ke_schedule_system_desc,
    late_id: SystemId = 0,
    remove: SystemId = 0,
    remove_late: bool = false,
    nested: abi_result.c.ke_result = R.ok,
    nested_set: abi_result.c.ke_result = R.ok,
};

fn registering(_: ?*c.ke_schedule_ctx, ud: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
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
    var nested_done: ?*abi_completion.c.ke_completion = null;
    r.nested = r.sched.run.?(r.sched, 0, &nested_done);
    var set: SetId = undefined;
    r.nested_set = r.sched.register_set.?(r.sched, &.{ .name = "inner" }, &set);
    return R.ok;
}

test "a system registered from a body runs from the next run on, and a run or a set from a body is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var late = Probe{};
    var reg = Registrar{ .sched = rig.sched, .late = rig.desc("late", &late) };
    _ = try rig.add(.{ .name = "registrar", .user_data = &reg, .execute = &registering, .sets = &rig.set, .set_count = 1 });
    try rig.run();
    try testing.expectEqual(0, late.calls.load(.monotonic));
    try testing.expectEqual(R.code(error.NotSupported), reg.nested);
    try testing.expectEqual(R.code(error.NotSupported), reg.nested_set);
    try rig.run();
    try testing.expectEqual(1, late.calls.load(.monotonic));
}

test "a system registered and unregistered by the same body never runs" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var late = Probe{};
    var reg = Registrar{ .sched = rig.sched, .late = rig.desc("late", &late), .remove_late = true };
    _ = try rig.add(.{ .name = "registrar", .user_data = &reg, .execute = &registering, .sets = &rig.set, .set_count = 1 });
    try rig.run();
    try rig.run();
    try testing.expectEqual(0, late.calls.load(.monotonic));
}

test "a system unregistered from a body stops running from the next run" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var victim = Probe{};
    const victim_id = try rig.add(rig.desc("victim", &victim));
    var reg = Registrar{ .sched = rig.sched, .late = rig.desc("late", &victim), .late_id = 1, .remove = victim_id };
    _ = try rig.add(.{ .name = "registrar", .user_data = &reg, .execute = &registering, .sets = &rig.set, .set_count = 1 });
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
    const id = try rig.add(rig.desc("gone", &gone));
    _ = try rig.add(rig.desc("kept", &kept));
    try R.check(rig.sched.unregister_system.?(rig.sched, id));
    try rig.run();
    try testing.expectEqual(0, gone.calls.load(.monotonic));
    try testing.expectEqual(1, kept.calls.load(.monotonic));
    try testing.expectEqual(R.code(error.NotFound), rig.sched.unregister_system.?(rig.sched, id));
    try testing.expectEqual(R.code(error.NotFound), rig.sched.unregister_system.?(rig.sched, 99));
}

fn spawning(ctx: ?*c.ke_schedule_ctx, _: ?*anyopaque, _: f32) callconv(.c) abi_result.c.ke_result {
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
    _ = try rig.add(.{ .name = "spawner", .execute = &spawning, .sets = &rig.set, .set_count = 1 });
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
    args[6].?.* = 6;
    return R.ok;
}

test "a query matching more segments than its buffer holds is resolved again into a bigger one and seen whole" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    _ = rig.ecs.when(.query_resolve).does(&manySegments);
    var probe = Probe{};
    const terms = [_]Term{term(1, read)};
    const query = [_]abi_ecs.c.ke_ecs_query_desc{queryOf(&terms, &.{}, &.{})};
    var desc = rig.desc("viewer", &probe);
    desc.queries = &query;
    desc.query_count = 1;
    _ = try rig.add(desc);
    try rig.run();
    try testing.expectEqual(6, probe.segments);
    try rig.ecs.received(.query_resolve).times(2);
    try rig.ecs.received(.query_register).times(1);
}

test "a system whose condition answers false resolves none of its queries" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{ .allow = false };
    const terms = [_]Term{term(1, read)};
    const query = [_]abi_ecs.c.ke_ecs_query_desc{queryOf(&terms, &.{}, &.{})};
    var desc = rig.desc("idle", &probe);
    desc.queries = &query;
    desc.query_count = 1;
    desc.condition = &allowed;
    _ = try rig.add(desc);
    try rig.run();
    try rig.ecs.received(.query_resolve).times(0);
}

test "a negative dt or a missing completion is refused" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var done: ?*abi_completion.c.ke_completion = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.run.?(rig.sched, -1, &done));
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.run.?(rig.sched, 0, null));
}

test "a schedule reads a component a query term or an access entry reads, and not one it only writes" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var probe = Probe{};
    const terms = [_]Term{ term(1, read), term(2, write) };
    const query = [_]abi_ecs.c.ke_ecs_query_desc{queryOf(&terms, &.{}, &.{})};
    const access = [_]Term{term(3, read | write)};
    var desc = rig.desc("reader", &probe);
    desc.queries = &query;
    desc.query_count = 1;
    desc.access = &access;
    desc.access_count = 1;
    _ = try rig.add(desc);
    try testing.expect(rig.sched.reads.?(rig.sched, 1));
    try testing.expect(!rig.sched.reads.?(rig.sched, 2));
    try testing.expect(rig.sched.reads.?(rig.sched, 3));
    try testing.expect(!rig.sched.reads.?(rig.sched, 4));
}

test "creating a schedule without an ecs, a job system or a config is refused and leaves the handle zeroed" {
    var ecs: zsub.For(abi_ecs.c.ke_ecs) = undefined;
    try ecs.init();
    defer ecs.deinit();
    var jobs: zsub.For(abi_job.c.ke_job_system) = undefined;
    try jobs.init();
    defer jobs.deinit();
    var handle: c.ke_schedule_handle = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), ke_schedule_create(null, jobs.api(), &.{ .refuse_ambiguity = false }, &handle));
    try testing.expectEqual(null, handle.ref);
    try testing.expectEqual(R.code(error.InvalidArgument), ke_schedule_create(ecs.api(), null, &.{ .refuse_ambiguity = false }, &handle));
    try testing.expectEqual(R.code(error.InvalidArgument), ke_schedule_create(ecs.api(), jobs.api(), null, &handle));
}

test "a slot given no schedule refuses" {
    var rig: Rig = undefined;
    try rig.init(1);
    defer rig.deinit();
    var id: SetId = undefined;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.register_set.?(null, &.{ .name = "x" }, &id));
    var done: ?*abi_completion.c.ke_completion = null;
    try testing.expectEqual(R.code(error.InvalidArgument), rig.sched.run.?(null, 0, &done));
    try testing.expectEqual(null, rig.sched.commands.?(null));
}

test "nothing the schedule allocated is left behind" {
    try heap.expectNoLeaks();
}
