//! Orders the systems of one phase into waves and marks the ones it culls. A system runs after the
//! systems of every set its own sets follow, an exclusive system before every other, a writer of an
//! id before a system that only reads it, and of two writers with no other order the one registered
//! first, reported as an ambiguity.

const std = @import("std");

const abi_scheduler = @import("abi_scheduler");
const heap = @import("heap");

const c = abi_scheduler.c;
const Id = c.ke_component_id;

/// A member of an exclusive group, as `declare_exclusive` stored it.
pub const Exclusive = struct { group: Id, member: Id };

/// One system of the phase. `access` holds its query terms merged with `explicit`, the access it
/// declared beside its queries; `sets` holds indices into the phase's set closure.
pub const Node = struct {
    name: [:0]const u8,
    exclusive: bool,
    access: []const c.ke_id_access,
    explicit: []const c.ke_id_access,
    queries: []const []const c.ke_id_access,
    sets: []const u32,
};

/// What stopped or troubled the order of a phase.
pub const Problem = union(enum) {
    none,
    out_of_memory,
    cycle: [:0]const u8,
    ambiguity: struct { first: [:0]const u8, second: [:0]const u8, id: Id },
};

/// The number of waves, the problem that stopped the order, and the first ambiguity, which does not.
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

fn writes(a: c.ke_id_access) bool {
    return (a.access & c.KE_SCHEDULER_ACCESS_WRITE) != 0;
}

fn reads(a: c.ke_id_access) bool {
    return (a.access & c.KE_SCHEDULER_ACCESS_READ) != 0;
}

fn touches(list: []const c.ke_id_access, id: Id, out_writes: *bool) bool {
    var any = false;
    out_writes.* = false;
    for (list) |a| {
        if (a.id != id) continue;
        any = true;
        if (writes(a)) out_writes.* = true;
    }
    return any;
}

fn memberOf(exclusive: []const Exclusive, id: Id) ?Exclusive {
    for (exclusive) |e| if (e.member == id) return e;
    return null;
}

/// The member of an exclusive group that every query of the system requires; null when it has no
/// query, a query requires none, or two queries require different ones.
fn confinement(n: Node, exclusive: []const Exclusive) ?Exclusive {
    var found: ?Exclusive = null;
    for (n.queries) |q| {
        var in_query: ?Exclusive = null;
        for (q) |t| {
            if (memberOf(exclusive, t.id)) |e| in_query = e;
        }
        const e = in_query orelse return null;
        if (found) |f| {
            if (f.member != e.member) return null;
        } else found = e;
    }
    return found;
}

fn inExplicit(n: Node, id: Id) bool {
    for (n.explicit) |a| if (a.id == id) return true;
    return false;
}

const Relation = struct { forward: bool = false, backward: bool = false, ambiguous: ?Id = null };

fn relate(a: Node, b: Node, exclusive: []const Exclusive) Relation {
    var r = Relation{};
    const ca = confinement(a, exclusive);
    const cb = confinement(b, exclusive);
    const disjoint = ca != null and cb != null and ca.?.group == cb.?.group and ca.?.member != cb.?.member;
    for (a.access) |entry| {
        var b_writes = false;
        if (!touches(b.access, entry.id, &b_writes)) continue;
        const a_writes = writes(entry);
        if (!a_writes and !b_writes) continue;
        if (disjoint and !inExplicit(a, entry.id) and !inExplicit(b, entry.id)) continue;
        if (a_writes and b_writes) {
            if (r.ambiguous == null) r.ambiguous = entry.id;
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

/// Orders the systems of one phase, given in registration order, and writes the wave of each into
/// `out_waves`. `follows` is the closure `closeSets` built for the phase's `set_count` sets. A cycle
/// fails the order, leaving the waves unwritten.
pub fn order(nodes: []const Node, follows: []const bool, set_count: usize, exclusive: []const Exclusive, out_waves: []u32) Order {
    var result = Order{};
    const n = nodes.len;
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

fn readsId(n: Node, id: Id) bool {
    for (n.access) |a| {
        if (a.id == id and reads(a)) return true;
    }
    return false;
}

fn cullable(nodes: []const Node, i: usize, short_lived: []const Id, culled: []const bool) bool {
    var writes_any = false;
    for (nodes[i].access) |a| {
        if (!writes(a)) continue;
        writes_any = true;
        if (std.mem.indexOfScalar(Id, short_lived, a.id) == null) return false;
        for (nodes, culled, 0..) |other, gone, j| {
            if (j != i and !gone and readsId(other, a.id)) return false;
        }
    }
    return writes_any;
}

/// Marks in `out_culled` the systems whose every write is one of `short_lived`, the ids that live
/// only within the phase, and that no other system still running reads, until a pass culls nothing.
pub fn cull(nodes: []const Node, short_lived: []const Id, out_culled: []bool) void {
    @memset(out_culled, false);
    if (short_lived.len == 0) return;
    var changed = true;
    while (changed) {
        changed = false;
        for (0..nodes.len) |i| {
            if (out_culled[i] or !cullable(nodes, i, short_lived, out_culled)) continue;
            out_culled[i] = true;
            changed = true;
        }
    }
}
