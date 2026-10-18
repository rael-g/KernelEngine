//! Cuts the systems of a phase into waves: consecutive systems that share no component one of them
//! writes run together, in registration order.

const std = @import("std");

const c = @import("c");
const heap = @import("heap");
const alloc = @import("runtime_alloc.zig");
const cAlloc = alloc.cAlloc;
const cFree = alloc.cFree;
const cAllocBytes = alloc.cAllocBytes;
const cFreeBytes = alloc.cFreeBytes;

const E = @import("kerror").Errors(c);

const ACCESS_WRITE: c_uint = @intCast(c.KE_ACCESS_WRITE);

pub fn termWrites(a: c.ke_component_access) bool {
    return (@as(c_uint, @intCast(a.access)) & ACCESS_WRITE) != 0;
}

pub fn paramsAccesses(p: *const c.ke_runtime_system_params, cid: c.ke_component_id, out_writes: *bool) bool {
    var any = false;
    var writes = false;
    if (p.queries) |queries| {
        for (0..p.query_count) |q| {
            const terms = queries[q].terms orelse continue;
            for (0..queries[q].term_count) |t| {
                if (terms[t].cid == cid) {
                    any = true;
                    if (termWrites(terms[t])) writes = true;
                }
            }
        }
    }
    if (p.access_list) |list| {
        for (0..p.access_count) |i| {
            if (list[i].cid == cid) {
                any = true;
                if (termWrites(list[i])) writes = true;
            }
        }
    }
    out_writes.* = writes;
    return any;
}

pub fn conflictOnTerm(b: *const c.ke_runtime_system_params, cid: c.ke_component_id, a_writes: bool) bool {
    var b_writes = false;
    return paramsAccesses(b, cid, &b_writes) and (a_writes or b_writes);
}

/// Reports whether two systems must not share a wave: they name a common component and at least
/// one of them writes it. Both arguments are registered parameters, whose queries `buildSystem`
/// has already folded into the access list.
pub fn systemsConflict(a: *const c.ke_runtime_system_params, b: *const c.ke_runtime_system_params) bool {
    if (a.queries) |queries| {
        for (0..a.query_count) |q| {
            const terms = queries[q].terms orelse continue;
            for (0..queries[q].term_count) |t| {
                const a_writes = termWrites(terms[t]);
                if (conflictOnTerm(b, terms[t].cid, a_writes)) return true;
            }
        }
    }
    if (a.access_list) |list| {
        for (0..a.access_count) |i| {
            const a_writes = termWrites(list[i]);
            if (conflictOnTerm(b, list[i].cid, a_writes)) return true;
        }
    }
    return false;
}

/// Assigns the systems of one phase, given in registration order, to waves. A system joins the
/// current wave unless it conflicts with a system already in it, in which case it opens the next
/// wave; a closed wave is never reopened, so registration order is never overtaken. The count
/// stays zero, with nothing reported, when there are no systems or a pointer is null.
pub fn debugComputeWaves(
    systems: [*c]const c.ke_runtime_system_params,
    system_count: u32,
    out_wave_assignments: [*c]u32,
    out_wave_count: [*c]u32,
) callconv(.c) void {
    if (out_wave_count == null) return;
    out_wave_count.* = 0;
    if (system_count == 0) return;
    if (systems == null or out_wave_assignments == null) return;

    var current_wave: u32 = 0;
    out_wave_assignments[0] = 0;
    var wave_start: u32 = 0;

    var i: u32 = 0;
    while (i < system_count) : (i += 1) {
        if (i == 0) {
            out_wave_assignments[0] = 0;
            continue;
        }
        var open_new = false;
        var j: u32 = wave_start;
        const si_ptr: *const c.ke_runtime_system_params = @ptrCast(&systems[i]);
        while (j < i) : (j += 1) {
            if (out_wave_assignments[j] != current_wave) continue;
            const sj_ptr: *const c.ke_runtime_system_params = @ptrCast(&systems[j]);
            if (systemsConflict(si_ptr, sj_ptr)) {
                open_new = true;
                break;
            }
        }
        if (open_new) {
            current_wave += 1;
            wave_start = i;
        }
        out_wave_assignments[i] = current_wave;
    }
    out_wave_count.* = current_wave + 1;
}
