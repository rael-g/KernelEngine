//! Orders the systems of one schedule into waves. A system runs after the systems of every set its
//! own sets follow, an exclusive system before every other, a writer of a component before a system
//! that only reads it, and of two writers with no other order the one registered first, reported as
//! an ambiguity. Systems whose queries can match no common entity do not conflict.

const std = @import("std");

const abi_ecs = @import("abi_ecs");
const abi_schedule = @import("abi_schedule");
const heap = @import("heap");

const c = abi_schedule.c;
const Id = c.ke_component_id;

/// A member of an exclusive group, as `declare_exclusive` stored it.
pub const Exclusive = struct { group: Id, member: Id };

const Term = abi_ecs.c.ke_ecs_query_term;

/// One query of a system: the components it hands columns of, those it requires without a column,
/// and those it excludes.
pub const Query = struct {
    terms: []const Term,
    with: []const Id,
    without: []const Id,
};

/// One system of the schedule. `access` holds its query terms merged with `explicit`, the access it
/// declared beside its queries; `sets` holds indices into the schedule's set closure.
pub const Node = struct {
    name: [:0]const u8,
    exclusive: bool,
    access: []const Term,
    explicit: []const Term,
    queries: []const Query,
    sets: []const u32,
};

/// What stopped or troubled the order of a schedule.
pub const Problem = union(enum) {
    none,
    out_of_memory,
    cycle: [:0]const u8,
    ambiguity: struct { first: [:0]const u8, second: [:0]const u8, id: Id },
};

/// The number of waves, the problem that stopped the order, and the first ambiguity, which does not;
/// every system in an ambiguity is marked in the `ambiguous` given to `order`.
pub const Order = struct {
    wave_count: u32 = 0,
    failure: Problem = .none,
    ambiguity: Problem = .none,
};

/// Closes the `after` lists of `count` sets into `out_follows`, where `out_follows[a * count + b]`
/// says set `a` runs after set `b`. Returns the index of a set that follows itself, or null.
pub fn closeSets(after: []const []const u32, out_follows: []bool) ?usize {
    const n = after.len;
    @memset(out_follows, false);
    for (after, 0..) |list, a| {
        for (list) |b| out_follows[a * n + b] = true;
    }
    for (0..n) |k| {
        for (0..n) |a| {
            if (!out_follows[a * n + k]) continue;
            for (0..n) |b| {
                if (out_follows[k * n + b]) out_follows[a * n + b] = true;
            }
        }
    }
    for (0..n) |a| {
        if (out_follows[a * n + a]) return a;
    }
    return null;
}

fn writes(a: Term) bool {
    return (@as(c_uint, @intCast(a.access)) & abi_ecs.c.KE_ECS_ACCESS_WRITE) != 0;
}

fn touches(list: []const Term, id: Id, out_writes: *bool) bool {
    var any = false;
    out_writes.* = false;
    for (list) |a| {
        if (a.component != id) continue;
        any = true;
        if (writes(a)) out_writes.* = true;
    }
    return any;
}

fn requires(q: Query, id: Id) bool {
    for (q.terms) |t| if (t.component == id) return true;
    return std.mem.indexOfScalar(Id, q.with, id) != null;
}

fn memberOf(exclusive: []const Exclusive, id: Id) ?Exclusive {
    for (exclusive) |e| if (e.member == id) return e;
    return null;
}

/// Whether no entity can match both queries: one requires a component the other excludes, or they
/// require different members of one exclusive group.
fn queriesDisjoint(a: Query, b: Query, exclusive: []const Exclusive) bool {
    for (a.without) |id| if (requires(b, id)) return true;
    for (b.without) |id| if (requires(a, id)) return true;
    for (exclusive) |ea| {
        if (!requires(a, ea.member)) continue;
        for (exclusive) |eb| {
            if (eb.group == ea.group and eb.member != ea.member and requires(b, eb.member)) return true;
        }
    }
    return false;
}

/// Whether every query of one system is disjoint from every query of the other; a system with no
/// query touches no entity set to compare.
fn systemsDisjoint(a: Node, b: Node, exclusive: []const Exclusive) bool {
    if (a.queries.len == 0 or b.queries.len == 0) return false;
    for (a.queries) |qa| {
        for (b.queries) |qb| if (!queriesDisjoint(qa, qb, exclusive)) return false;
    }
    return true;
}

fn inExplicit(n: Node, id: Id) bool {
    for (n.explicit) |a| if (a.component == id) return true;
    return false;
}

const Relation = struct { forward: bool = false, backward: bool = false, ambiguous: ?Id = null };

fn relate(a: Node, b: Node, exclusive: []const Exclusive) Relation {
    var r = Relation{};
    const disjoint = systemsDisjoint(a, b, exclusive);
    for (a.access) |entry| {
        var b_writes = false;
        if (!touches(b.access, entry.component, &b_writes)) continue;
        const a_writes = writes(entry);
        if (!a_writes and !b_writes) continue;
        if (disjoint and !inExplicit(a, entry.component) and !inExplicit(b, entry.component)) continue;
        if (a_writes and b_writes) {
            if (r.ambiguous == null) r.ambiguous = entry.component;
        } else if (a_writes) {
            r.forward = true;
        } else {
            r.backward = true;
        }
    }
    return r;
}

fn setFollows(later: Node, earlier: Node, follows: []const bool, set_count: usize) bool {
    for (later.sets) |l| {
        for (earlier.sets) |e| {
            if (follows[l * set_count + e]) return true;
        }
    }
    return false;
}

/// Orders the systems of one schedule, given in registration order, and writes the wave of each into
/// `out_waves` and whether it is in an ambiguity into `out_ambiguous`. `follows` is the closure
/// `closeSets` built for the schedule's `set_count` sets. A cycle fails the order, leaving the waves
/// unwritten.
pub fn order(nodes: []const Node, follows: []const bool, set_count: usize, exclusive: []const Exclusive, out_waves: []u32, out_ambiguous: []bool) Order {
    var result = Order{};
    const n = nodes.len;
    @memset(out_ambiguous, false);
    if (n == 0) return result;

    const edges = heap.gpa.alloc(bool, n * n) catch return .{ .failure = .out_of_memory };
    defer heap.gpa.free(edges);
    @memset(edges, false);

    for (0..n) |i| {
        for (i + 1..n) |j| {
            const a = nodes[i];
            const b = nodes[j];
            const b_after_a = setFollows(b, a, follows, set_count);
            const a_after_b = setFollows(a, b, follows, set_count);
            if (b_after_a or a_after_b) {
                if (b_after_a) edges[i * n + j] = true;
                if (a_after_b) edges[j * n + i] = true;
                continue;
            }
            if (a.exclusive != b.exclusive) {
                if (a.exclusive) edges[i * n + j] = true else edges[j * n + i] = true;
                continue;
            }
            if (a.exclusive) {
                edges[i * n + j] = true;
                out_ambiguous[i] = true;
                out_ambiguous[j] = true;
                if (result.ambiguity == .none)
                    result.ambiguity = .{ .ambiguity = .{ .first = a.name, .second = b.name, .id = 0 } };
                continue;
            }
            const r = relate(a, b, exclusive);
            if (r.forward) edges[i * n + j] = true;
            if (r.backward) edges[j * n + i] = true;
            if (!r.forward and !r.backward) {
                if (r.ambiguous) |id| {
                    edges[i * n + j] = true;
                    out_ambiguous[i] = true;
                    out_ambiguous[j] = true;
                    if (result.ambiguity == .none)
                        result.ambiguity = .{ .ambiguity = .{ .first = a.name, .second = b.name, .id = id } };
                }
            }
        }
    }

    const pending = heap.gpa.alloc(u32, n) catch return .{ .failure = .out_of_memory };
    defer heap.gpa.free(pending);
    const done = heap.gpa.alloc(bool, n) catch return .{ .failure = .out_of_memory };
    defer heap.gpa.free(done);
    @memset(done, false);
    for (0..n) |v| {
        var count: u32 = 0;
        for (0..n) |u| {
            if (edges[u * n + v]) count += 1;
        }
        pending[v] = count;
        out_waves[v] = 0;
    }

    var placed: usize = 0;
    while (placed < n) {
        var progressed = false;
        for (0..n) |u| {
            if (done[u] or pending[u] != 0) continue;
            done[u] = true;
            placed += 1;
            progressed = true;
            result.wave_count = @max(result.wave_count, out_waves[u] + 1);
            for (0..n) |v| {
                if (!edges[u * n + v]) continue;
                pending[v] -= 1;
                out_waves[v] = @max(out_waves[v], out_waves[u] + 1);
            }
        }
        if (!progressed) {
            for (0..n) |u| {
                if (!done[u]) return .{ .failure = .{ .cycle = nodes[u].name } };
            }
        }
    }
    return result;
}
