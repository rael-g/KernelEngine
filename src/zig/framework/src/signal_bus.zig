
const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap");

const E = @import("kerror").Errors(c);

const name_max = 64;

const unknown_size: u32 = c.KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN;

const default_max_signals = 64;
const default_max_connections = 512;
const default_max_events = 256;
const default_max_deliveries = 512;
const default_payload_capacity = 16 * 1024;

const Signal = struct {
    name: [name_max]u8,
    name_len: usize,
    payload_size: u32,
};

const Connection = struct {
    source: c.ke_entity,
    signal_id: u32,
    target: c.ke_entity,
    handler_id: u32,
};

const Event = struct {
    source: c.ke_entity,
    signal_id: u32,
    payload_offset: u32,
    payload_size: u32,
};

const State = struct {
    api: c.ke_signal_bus,

    signals: []Signal,
    signal_count: u32,

    connections: []Connection,
    connection_count: u32,

    events: []Event,
    event_count: u32,

    payloads: []u8,
    payload_used: u32,

    deliveries: []c.ke_signal_delivery,
    delivery_count: u32,
    joined: bool,
};

fn stateOf(self: *c.ke_signal_bus) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn orDefault(v: u32, d: u32) u32 {
    return if (v == 0) d else v;
}

fn signalId(
    self_in: ?*c.ke_signal_bus,
    name_in: [*c]const u8,
    payload_size: u32,
    out_id: [*c]u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "signal bus is null", @src());
        return false;
    };
    if (name_in == null or out_id == null) {
        E.fail(out_error, .invalid_argument, "signal name and out_id are required", @src());
        return false;
    }
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    if (name.len == 0 or name.len >= name_max) {
        E.fail(out_error, .invalid_argument, "signal name is empty or too long", @src());
        return false;
    }

    for (s.signals[0..s.signal_count], 0..) |*sig, i| {
        if (!std.mem.eql(u8, sig.name[0..sig.name_len], name)) continue;
        if (payload_size != unknown_size) {
            if (sig.payload_size == unknown_size) {
                sig.payload_size = payload_size;
            } else if (sig.payload_size != payload_size) {
                E.fail(out_error, .already_exists, "signal already registered with a different payload size", @src());
                return false;
            }
        }
        out_id.* = @intCast(i);
        return true;
    }

    if (s.signal_count == s.signals.len) {
        E.fail(out_error, .out_of_memory, "signal table is full", @src());
        return false;
    }
    var sig = Signal{ .name = undefined, .name_len = name.len, .payload_size = payload_size };
    @memcpy(sig.name[0..name.len], name);
    s.signals[s.signal_count] = sig;
    out_id.* = s.signal_count;
    s.signal_count += 1;
    return true;
}

fn signalLookup(
    self_in: ?*c.ke_signal_bus,
    name_in: [*c]const u8,
    out_id: [*c]u32,
) callconv(.c) bool {
    const self = self_in orelse return false;
    if (name_in == null or out_id == null) return false;
    const s = stateOf(self);
    const name = std.mem.span(name_in);
    for (s.signals[0..s.signal_count], 0..) |*sig, i| {
        if (!std.mem.eql(u8, sig.name[0..sig.name_len], name)) continue;
        out_id.* = @intCast(i);
        return true;
    }
    return false;
}

fn connect(
    self_in: ?*c.ke_signal_bus,
    source: c.ke_entity,
    signal_id: u32,
    target: c.ke_entity,
    handler_id: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "signal bus is null", @src());
        return false;
    };
    const s = stateOf(self);
    if (signal_id >= s.signal_count) {
        E.fail(out_error, .not_found, "signal id was never registered", @src());
        return false;
    }
    for (s.connections[0..s.connection_count]) |conn| {
        if (conn.source == source and conn.signal_id == signal_id and
            conn.target == target and conn.handler_id == handler_id) return true;
    }
    if (s.connection_count == s.connections.len) {
        E.fail(out_error, .out_of_memory, "connection table is full", @src());
        return false;
    }
    s.connections[s.connection_count] = .{
        .source = source,
        .signal_id = signal_id,
        .target = target,
        .handler_id = handler_id,
    };
    s.connection_count += 1;
    return true;
}

fn removeConnectionAt(s: *State, i: u32) void {
    s.connections[i] = s.connections[s.connection_count - 1];
    s.connection_count -= 1;
}

fn disconnect(
    self_in: ?*c.ke_signal_bus,
    source: c.ke_entity,
    signal_id: u32,
    target: c.ke_entity,
    handler_id: u32,
) callconv(.c) bool {
    const self = self_in orelse return false;
    const s = stateOf(self);
    var i: u32 = 0;
    while (i < s.connection_count) : (i += 1) {
        const conn = s.connections[i];
        if (conn.source == source and conn.signal_id == signal_id and
            conn.target == target and conn.handler_id == handler_id)
        {
            removeConnectionAt(s, i);
            return true;
        }
    }
    return false;
}

fn forgetEntity(self_in: ?*c.ke_signal_bus, entity: c.ke_entity) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    var i: u32 = 0;
    while (i < s.connection_count) {
        const conn = s.connections[i];
        if (conn.source == entity or conn.target == entity) {
            removeConnectionAt(s, i);
            continue;
        }
        i += 1;
    }
}

fn emit(
    self_in: ?*c.ke_signal_bus,
    source: c.ke_entity,
    signal_id: u32,
    payload: ?*const anyopaque,
    payload_size: u32,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "signal bus is null", @src());
        return false;
    };
    const s = stateOf(self);
    if (signal_id >= s.signal_count) {
        E.fail(out_error, .not_found, "signal id was never registered", @src());
        return false;
    }
    if (s.signals[signal_id].payload_size == unknown_size) {
        E.fail(out_error, .not_initialized, "signal's payload layout was never declared", @src());
        return false;
    }
    if (payload_size != s.signals[signal_id].payload_size) {
        E.fail(out_error, .invalid_argument, "payload size does not match the registered signal", @src());
        return false;
    }
    if (s.event_count == s.events.len) {
        E.fail(out_error, .out_of_memory, "frame event buffer is full", @src());
        return false;
    }
    if (s.payload_used + payload_size > s.payloads.len) {
        E.fail(out_error, .out_of_memory, "frame payload storage is full", @src());
        return false;
    }

    const offset = s.payload_used;
    if (payload_size > 0) {
        const src: [*]const u8 = @ptrCast(payload orelse {
            E.fail(out_error, .invalid_argument, "signal carries a payload but none was given", @src());
            return false;
        });
        @memcpy(s.payloads[offset .. offset + payload_size], src[0..payload_size]);
        s.payload_used += payload_size;
    }

    s.events[s.event_count] = .{
        .source = source,
        .signal_id = signal_id,
        .payload_offset = offset,
        .payload_size = payload_size,
    };
    s.event_count += 1;
    s.joined = false;
    return true;
}

fn deliveries(self_in: ?*c.ke_signal_bus, out_count: [*c]u32) callconv(.c) [*c]const c.ke_signal_delivery {
    const self = self_in orelse {
        if (out_count != null) out_count.* = 0;
        return null;
    };
    const s = stateOf(self);
    if (!s.joined) {
        s.delivery_count = 0;
        outer: for (s.events[0..s.event_count]) |ev| {
            for (s.connections[0..s.connection_count]) |conn| {
                if (conn.source != ev.source or conn.signal_id != ev.signal_id) continue;
                if (s.delivery_count == s.deliveries.len) break :outer;
                s.deliveries[s.delivery_count] = .{
                    .source = ev.source,
                    .target = conn.target,
                    .signal_id = ev.signal_id,
                    .handler_id = conn.handler_id,
                    .payload = if (ev.payload_size > 0) &s.payloads[ev.payload_offset] else null,
                    .payload_size = ev.payload_size,
                };
                s.delivery_count += 1;
            }
        }
        s.joined = true;
    }
    if (out_count != null) out_count.* = s.delivery_count;
    return s.deliveries.ptr;
}

fn clearFrame(self_in: ?*c.ke_signal_bus) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    s.event_count = 0;
    s.payload_used = 0;
    s.delivery_count = 0;
    s.joined = true;
}

fn destroy(self_in: ?*c.ke_signal_bus) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    heap.gpa.free(s.signals);
    heap.gpa.free(s.connections);
    heap.gpa.free(s.events);
    heap.gpa.free(s.payloads);
    heap.gpa.free(s.deliveries);
    heap.gpa.destroy(s);
}

pub export fn ke_signal_bus_create(
    params: [*c]const c.ke_signal_bus_params,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_signal_bus_handle {
    const null_handle = std.mem.zeroes(c.ke_signal_bus_handle);

    const n_signals = if (params != null) orDefault(params.*.max_signals, default_max_signals) else default_max_signals;
    const n_connections = if (params != null) orDefault(params.*.max_connections, default_max_connections) else default_max_connections;
    const n_events = if (params != null) orDefault(params.*.max_events, default_max_events) else default_max_events;
    const n_deliveries = if (params != null) orDefault(params.*.max_deliveries, default_max_deliveries) else default_max_deliveries;
    const n_payload = if (params != null) orDefault(params.*.payload_capacity, default_payload_capacity) else default_payload_capacity;

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "signal bus allocation failed", @src());
        return null_handle;
    };
    errdefer heap.gpa.destroy(s);

    s.signals = heap.gpa.alloc(Signal, n_signals) catch {
        E.fail(out_error, .out_of_memory, "signal table allocation failed", @src());
        heap.gpa.destroy(s);
        return null_handle;
    };
    s.connections = heap.gpa.alloc(Connection, n_connections) catch {
        E.fail(out_error, .out_of_memory, "connection table allocation failed", @src());
        heap.gpa.free(s.signals);
        heap.gpa.destroy(s);
        return null_handle;
    };
    s.events = heap.gpa.alloc(Event, n_events) catch {
        E.fail(out_error, .out_of_memory, "event buffer allocation failed", @src());
        heap.gpa.free(s.connections);
        heap.gpa.free(s.signals);
        heap.gpa.destroy(s);
        return null_handle;
    };
    s.payloads = heap.gpa.alloc(u8, n_payload) catch {
        E.fail(out_error, .out_of_memory, "payload storage allocation failed", @src());
        heap.gpa.free(s.events);
        heap.gpa.free(s.connections);
        heap.gpa.free(s.signals);
        heap.gpa.destroy(s);
        return null_handle;
    };
    s.deliveries = heap.gpa.alloc(c.ke_signal_delivery, n_deliveries) catch {
        E.fail(out_error, .out_of_memory, "delivery buffer allocation failed", @src());
        heap.gpa.free(s.payloads);
        heap.gpa.free(s.events);
        heap.gpa.free(s.connections);
        heap.gpa.free(s.signals);
        heap.gpa.destroy(s);
        return null_handle;
    };

    s.signal_count = 0;
    s.connection_count = 0;
    s.event_count = 0;
    s.payload_used = 0;
    s.delivery_count = 0;
    s.joined = true;

    s.api = .{
        .handle = s,
        .signal_id = signalId,
        .signal_lookup = signalLookup,
        .connect = connect,
        .disconnect = disconnect,
        .forget_entity = forgetEntity,
        .emit = emit,
        .deliveries = deliveries,
        .clear_frame = clearFrame,
    };

    return .{ .ref = &s.api, .destroy = destroy };
}

const testing = std.testing;

const Payload = extern struct { left_scored: u8 };

fn makeBus() c.ke_signal_bus_handle {
    return ke_signal_bus_create(null, null);
}

test "an emission reaches every node connected to it and nobody else" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var goal: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "GoalScored", @sizeOf(Payload), &goal, null));

    try testing.expect(bus.connect.?(bus, 1, goal, 2, 7, null));
    try testing.expect(bus.connect.?(bus, 1, goal, 3, 9, null));
    try testing.expect(bus.connect.?(bus, 99, goal, 4, 0, null));

    const sent = Payload{ .left_scored = 1 };
    try testing.expect(bus.emit.?(bus, 1, goal, &sent, @sizeOf(Payload), null));

    var count: u32 = 0;
    const list = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 2), count);
    try testing.expectEqual(@as(c.ke_entity, 2), list[0].target);
    try testing.expectEqual(@as(u32, 7), list[0].handler_id);
    try testing.expectEqual(@as(c.ke_entity, 3), list[1].target);

    const got: *const Payload = @ptrCast(@alignCast(list[0].payload.?));
    try testing.expectEqual(@as(u8, 1), got.left_scored);
}

test "calling deliveries twice joins once, and a later emission still lands" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var sig: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "Ping", 0, &sig, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));
    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));

    var count: u32 = 0;
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);

    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 2), count);
}

test "clearing a frame drops emissions and keeps connections" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var sig: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "Ping", 0, &sig, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));
    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));

    bus.clear_frame.?(bus);
    var count: u32 = 1;
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 0), count);

    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);
}

test "the same signal name under a different payload size is rejected" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var a: u32 = 0;
    var b: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "GoalScored", 4, &a, null));
    try testing.expect(!bus.signal_id.?(bus, "GoalScored", 8, &b, null));
    try testing.expect(bus.signal_id.?(bus, "GoalScored", 4, &b, null));
    try testing.expectEqual(a, b);
}

test "connecting the same wire twice delivers once" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var sig: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "Ping", 0, &sig, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));
    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));

    var count: u32 = 0;
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);
}

test "forgetting an entity removes every wire it is either end of" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var sig: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "Ping", 0, &sig, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));
    try testing.expect(bus.connect.?(bus, 2, sig, 3, 0, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 3, 0, null));

    bus.forget_entity.?(bus, 2);

    try testing.expect(bus.emit.?(bus, 1, sig, null, 0, null));
    try testing.expect(bus.emit.?(bus, 2, sig, null, 0, null));
    var count: u32 = 0;
    const list = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);
    try testing.expectEqual(@as(c.ke_entity, 3), list[0].target);
}

test "emitting a payload of the wrong size fails instead of writing it" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var sig: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "GoalScored", @sizeOf(Payload), &sig, null));
    try testing.expect(bus.connect.?(bus, 1, sig, 2, 0, null));

    var wrong: u64 = 0;
    try testing.expect(!bus.emit.?(bus, 1, sig, &wrong, @sizeOf(u64), null));

    var count: u32 = 1;
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 0), count);
}

test "emitting an unregistered signal fails" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);
    try testing.expect(!bus.emit.?(bus, 1, 42, null, 0, null));
}

test "a signal wired by name before its layout is declared still resolves to one id" {
    const h = makeBus();
    defer h.destroy.?(h.ref);
    const bus: *c.ke_signal_bus = @ptrCast(h.ref);

    var wired: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "GoalScored", unknown_size, &wired, null));
    try testing.expect(bus.connect.?(bus, 1, wired, 2, 0, null));

    var p = Payload{ .left_scored = 1 };
    try testing.expect(!bus.emit.?(bus, 1, wired, &p, @sizeOf(Payload), null));

    var declared: u32 = 0;
    try testing.expect(bus.signal_id.?(bus, "GoalScored", @sizeOf(Payload), &declared, null));
    try testing.expectEqual(wired, declared);

    try testing.expect(bus.emit.?(bus, 1, declared, &p, @sizeOf(Payload), null));
    var count: u32 = 0;
    _ = bus.deliveries.?(bus, &count);
    try testing.expectEqual(@as(u32, 1), count);
}
