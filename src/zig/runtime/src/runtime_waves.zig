//! Orders the systems of a phase and cuts them into waves. Order comes from the names a system runs
//! after or before, from a writer running before a system that only reads what it writes, and,
//! between two writers with neither, from registration, reported as an ambiguity. An exclusive
//! system runs before every system that is not. Each system lands in the wave after the last of
//! those it follows.

const std = @import("std");

const c = @import("c");
const heap = @import("heap");
const QueryDecl = @import("runtime_queries.zig").QueryDecl;

const ACCESS_WRITE: c_uint = @intCast(c.KE_ACCESS_WRITE);

pub fn termWrites(a: c.ke_component_access) bool {
    return (@as(c_uint, @intCast(a.access)) & ACCESS_WRITE) != 0;
}

/// Whether the access list of `p` names `cid`, with `out_writes` set when one of its entries
/// writes it.
pub fn paramsAccesses(p: *const c.ke_runtime_system_params, cid: c.ke_component_id, out_writes: *bool) bool {
    var any = false;
    var writes = false;
    if (p.access_list) |list| {
        for (0..p.access_count) |i| {
            if (list[i].cid != cid) continue;
            any = true;
            if (termWrites(list[i])) writes = true;
        }
    }
    out_writes.* = writes;
    return any;
}

/// A member of an exclusive group, as `declare_exclusive` stored it.
pub const Exclusive = struct { group: c.ke_component_id, member: c.ke_component_id };

/// What the runtime was told beyond the systems: the exclusive groups and the components whose
/// writers their owner orders.
pub const Rules = struct {
    exclusive: []const Exclusive = &.{},
    self_ordered: []const c.ke_component_id = &.{},

    fn selfOrdered(self: Rules, cid: c.ke_component_id) bool {
        return std.mem.indexOfScalar(c.ke_component_id, self.self_ordered, cid) != null;
    }

    fn memberOf(self: Rules, cid: c.ke_component_id) ?Exclusive {
        for (self.exclusive) |e| if (e.member == cid) return e;
        return null;
    }
};

/// One system of the phase. `params` carries its name, its `after` and `before` and an access list
/// that already holds its query terms; `explicit` is the access list it declared beside its
/// queries, and `queries` the queries themselves.
pub const Node = struct {
    params: *const c.ke_runtime_system_params,
    explicit: []const c.ke_component_access = &.{},
    queries: []const QueryDecl = &.{},
};

/// What stopped or troubled the order of a phase.
pub const Problem = union(enum) {
    none,
    out_of_memory,
    unknown_name: struct { system: [*c]const u8, name: [*c]const u8 },
    cycle: struct { system: [*c]const u8 },
    ambiguity: struct { first: [*c]const u8, second: [*c]const u8, cid: c.ke_component_id },
};

/// The result of `order`: the number of waves, the first problem that stops the order, and the
/// first ambiguity, which does not.
pub const Order = struct {
    wave_count: u32 = 0,
    failure: Problem = .none,
    ambiguity: Problem = .none,
};

fn nameEql(a: [*c]const u8, b: [*c]const u8) bool {
    if (a == null or b == null) return false;
    return std.mem.eql(u8, std.mem.span(a), std.mem.span(b));
}

fn names(list: [*c]const [*c]const u8, count: u32) []const [*c]const u8 {
    if (list == null or count == 0) return &.{};
    return list[0..count];
}

fn listsName(list: []const [*c]const u8, name: [*c]const u8) bool {
    for (list) |n| if (nameEql(n, name)) return true;
    return false;
}

/// The member of an exclusive group that every query of the system requires; null when it has no
/// query, a query requires none, or two queries require different ones.
fn confinement(n: Node, rules: Rules) ?Exclusive {
    var found: ?Exclusive = null;
    for (n.queries) |q| {
        var in_query: ?Exclusive = null;
        for (q.terms[0..q.term_count]) |t| {
            if (rules.memberOf(t.cid)) |e| in_query = e;
        }
        const e = in_query orelse return null;
        if (found) |f| {
            if (f.member != e.member) return null;
        } else found = e;
    }
    return found;
}

fn inExplicit(n: Node, cid: c.ke_component_id) bool {
    for (n.explicit) |a| if (a.cid == cid) return true;
    return false;
}

const Relation = struct { forward: bool = false, backward: bool = false, ambiguous: ?c.ke_component_id = null };

/// How the data of `a`, registered before `b`, orders the two.
fn relate(a: Node, b: Node, rules: Rules) Relation {
    var r = Relation{};
    const ca = confinement(a, rules);
    const cb = confinement(b, rules);
    const disjoint = ca != null and cb != null and ca.?.group == cb.?.group and ca.?.member != cb.?.member;
    const list = a.params.access_list orelse return r;
    for (list[0..a.params.access_count]) |entry| {
        var b_writes = false;
        if (!paramsAccesses(b.params, entry.cid, &b_writes)) continue;
        const a_writes = termWrites(entry);
        if (!a_writes and !b_writes) continue;
        if (disjoint and !inExplicit(a, entry.cid) and !inExplicit(b, entry.cid)) continue;
        if (a_writes and b_writes) {
            if (rules.selfOrdered(entry.cid)) continue;
            if (r.ambiguous == null) r.ambiguous = entry.cid;
        } else if (a_writes) {
            r.forward = true;
        } else {
            r.backward = true;
        }
    }
    return r;
}

/// Orders the systems of one phase, given in registration order, and writes the wave of each into
/// `out_waves`. An `after` or `before` naming no system of the phase, and a cycle, fail the order;
/// the waves are then left unwritten.
pub fn order(nodes: []const Node, rules: Rules, out_waves: []u32) Order {
    var result = Order{};
    const n = nodes.len;
    if (n == 0) return result;

    for (nodes) |node| {
        const p = node.params;
        for ([_][]const [*c]const u8{ names(p.after, p.after_count), names(p.before, p.before_count) }) |list| {
            for (list) |wanted| {
                var known = false;
                for (nodes) |other| {
                    if (nameEql(other.params.name, wanted)) known = true;
                }
                if (!known) {
                    result.failure = .{ .unknown_name = .{ .system = p.name, .name = wanted } };
                    return result;
                }
            }
        }
    }

    const edges = heap.gpa.alloc(bool, n * n) catch {
        result.failure = .out_of_memory;
        return result;
    };
    defer heap.gpa.free(edges);
    @memset(edges, false);

    for (0..n) |i| {
        for (i + 1..n) |j| {
            const a = nodes[i].params;
            const b = nodes[j].params;
            const b_after_a = listsName(names(b.after, b.after_count), a.name) or listsName(names(a.before, a.before_count), b.name);
            const a_after_b = listsName(names(a.after, a.after_count), b.name) or listsName(names(b.before, b.before_count), a.name);
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
                    result.ambiguity = .{ .ambiguity = .{ .first = a.name, .second = b.name, .cid = 0 } };
                continue;
            }
            const r = relate(nodes[i], nodes[j], rules);
            if (r.forward) edges[i * n + j] = true;
            if (r.backward) edges[j * n + i] = true;
            if (!r.forward and !r.backward) {
                if (r.ambiguous) |cid| {
                    edges[i * n + j] = true;
                    if (result.ambiguity == .none)
                        result.ambiguity = .{ .ambiguity = .{ .first = a.name, .second = b.name, .cid = cid } };
                }
            }
        }
    }

    const pending = heap.gpa.alloc(u32, n) catch {
        result.failure = .out_of_memory;
        return result;
    };
    defer heap.gpa.free(pending);
    for (0..n) |v| {
        var count: u32 = 0;
        for (0..n) |u| {
            if (edges[u * n + v]) count += 1;
        }
        pending[v] = count;
        out_waves[v] = 0;
    }

    var placed: usize = 0;
    const done = heap.gpa.alloc(bool, n) catch {
        result.failure = .out_of_memory;
        return result;
    };
    defer heap.gpa.free(done);
    @memset(done, false);
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
                if (!done[u]) {
                    result.failure = .{ .cycle = .{ .system = nodes[u].params.name } };
                    return result;
                }
            }
        }
    }
    return result;
}
