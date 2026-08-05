// ke_node_host — the language-agnostic node-registration middle-end. Declaring
// a node type via begin_type/commit turns its fields into one ECS component
// and its hooks into one ke_runtime system per hook, verified atomically at
// commit(): either every field/hook/access is valid and everything registers,
// or nothing does. See docs/ScriptingArchitectureV2.md for the full design;
// docs/ScriptingArchitectureV3.md §7.14.4 for why this replaces reflection at
// the C# layer specifically.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

// -- field layout --------------------------------------------------------

// STRING/TABLE are not blittable into a raw component's memory — a variant
// carrying a pointer/table reference has no fixed in-place representation a
// query column can hand back as `void*`. Every other ke_variant_type maps to
// a fixed native size, independent of the variant union's own (wasteful,
// double/int64-sized) in-memory layout.
fn fieldSize(t: c.ke_variant_type) ?u32 {
    return switch (t) {
        c.KE_VARIANT_BOOL => 1,
        c.KE_VARIANT_INT => 4,
        c.KE_VARIANT_FLOAT => 4,
        c.KE_VARIANT_VEC2 => 8,
        c.KE_VARIANT_VEC3 => 12,
        c.KE_VARIANT_VEC4, c.KE_VARIANT_QUAT => 16,
        else => null,
    };
}

fn fieldAlign(t: c.ke_variant_type) u32 {
    return switch (t) {
        c.KE_VARIANT_BOOL => 1,
        else => 4,
    };
}

fn alignUp(x: u32, a: u32) u32 {
    return (x + a - 1) / a * a;
}

// -- builder state ---------------------------------------------------------

const FieldDecl = struct {
    name: []u8, // owned
    vtype: c.ke_variant_type,
    offset: u32,
    size: u32,
};

const AccessDecl = struct {
    hook: c.ke_node_hook_id,
    component_name: []u8, // owned
    access: c.ke_access,
};

const HookDecl = struct {
    id: c.ke_node_hook_id,
    kind: c.ke_node_hook_kind,
    fn_ptr: c.ke_node_hook_fn,
    ctx: ?*anyopaque,
};

const Builder = struct {
    api: c.ke_node_type_builder,
    host: *State,
    type_name: []u8, // owned
    fields: std.ArrayList(FieldDecl),
    hooks: std.ArrayList(HookDecl),
    accesses: std.ArrayList(AccessDecl),
    next_hook_id: c.ke_node_hook_id,

    fn deinit(self: *Builder) void {
        for (self.fields.items) |f| heap.gpa.free(f.name);
        for (self.accesses.items) |a| heap.gpa.free(a.component_name);
        self.fields.deinit(heap.gpa);
        self.hooks.deinit(heap.gpa);
        self.accesses.deinit(heap.gpa);
        heap.gpa.free(self.type_name);
        heap.gpa.destroy(self);
    }
};

fn builderOf(self: *c.ke_node_type_builder) *Builder {
    return @ptrCast(@alignCast(self.handle));
}

fn ownedCopy(s: []const u8) ![]u8 {
    const buf = try heap.gpa.alloc(u8, s.len);
    @memcpy(buf, s);
    return buf;
}

fn btField(self_in: ?*c.ke_node_type_builder, name: [*c]const u8, vtype: c.ke_variant_type) callconv(.c) bool {
    const self = self_in orelse return false;
    if (name == null) return false;
    const b = builderOf(self);
    const owned = ownedCopy(std.mem.span(name)) catch return false;
    b.fields.append(heap.gpa, .{ .name = owned, .vtype = vtype, .offset = 0, .size = 0 }) catch {
        heap.gpa.free(owned);
        return false;
    };
    return true;
}

fn btHook(self_in: ?*c.ke_node_type_builder, kind: c.ke_node_hook_kind, fn_ptr: c.ke_node_hook_fn, ctx: ?*anyopaque) callconv(.c) c.ke_node_hook_id {
    const self = self_in orelse return c.KE_NODE_HOOK_INVALID;
    if (fn_ptr == null) return c.KE_NODE_HOOK_INVALID;
    const b = builderOf(self);
    b.next_hook_id += 1;
    const id = b.next_hook_id;
    b.hooks.append(heap.gpa, .{ .id = id, .kind = kind, .fn_ptr = fn_ptr, .ctx = ctx }) catch return c.KE_NODE_HOOK_INVALID;
    return id;
}

fn btAccess(self_in: ?*c.ke_node_type_builder, hook: c.ke_node_hook_id, component_name: [*c]const u8, access: c.ke_access) callconv(.c) bool {
    const self = self_in orelse return false;
    if (component_name == null or hook == c.KE_NODE_HOOK_INVALID) return false;
    const b = builderOf(self);
    const owned = ownedCopy(std.mem.span(component_name)) catch return false;
    b.accesses.append(heap.gpa, .{ .hook = hook, .component_name = owned, .access = access }) catch {
        heap.gpa.free(owned);
        return false;
    };
    return true;
}

// -- committed type ----------------------------------------------------------

const HookDispatchCtx = struct {
    fn_ptr: c.ke_node_hook_fn,
    ctx: ?*anyopaque,
};

const NodeType = struct {
    name: []u8, // owned
    cid: c.ke_component_id,
    fields: []c.ke_component_field, // owned; field.name is separately owned utf8
    dispatch_ctxs: []*HookDispatchCtx, // owned, one per hook — kept alive for the runtime system's lifetime

    fn deinit(self: *NodeType) void {
        for (self.fields) |f| heap.gpa.free(std.mem.span(f.name));
        heap.gpa.free(self.fields);
        for (self.dispatch_ctxs) |d| heap.gpa.destroy(d);
        heap.gpa.free(self.dispatch_ctxs);
        heap.gpa.free(self.name);
        heap.gpa.destroy(self);
    }
};

const State = struct {
    api: c.ke_node_host,
    ecs: *c.ke_ecs,
    runtime: *c.ke_runtime,
    types: std.StringHashMapUnmanaged(*NodeType),
};

fn stateOf(self: *c.ke_node_host) *State {
    return @ptrCast(@alignCast(self.handle));
}

fn phaseFor(kind: c.ke_node_hook_kind) ?c.ke_phase {
    return switch (kind) {
        c.KE_NODE_HOOK_UPDATE => c.KE_PHASE_UPDATE,
        else => null,
    };
}

fn hookExecute(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, dt: f32) callconv(.c) void {
    const hd: *HookDispatchCtx = @ptrCast(@alignCast(user orelse return));
    var count: usize = 0;
    const segs = c.ke_system_ctx_view(ctx, 0, &count);
    if (segs == null) return;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const seg = segs[i];
        hd.fn_ptr.?(hd.ctx, seg.entities, &seg.columns, seg.count, dt);
    }
}

fn hostBeginType(self_in: ?*c.ke_node_host, type_name: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) ?*c.ke_node_type_builder {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    };
    if (type_name == null or type_name[0] == 0) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null;
    }
    const s = stateOf(self);
    const name = std.mem.span(type_name);
    if (s.types.contains(name)) {
        E.fail(out_error, .already_exists, "node type already committed", @src());
        return null;
    }

    const b = heap.gpa.create(Builder) catch {
        E.fail(out_error, .out_of_memory, "builder allocation failed", @src());
        return null;
    };
    const owned_name = ownedCopy(name) catch {
        heap.gpa.destroy(b);
        E.fail(out_error, .out_of_memory, "builder allocation failed", @src());
        return null;
    };
    b.* = .{
        .api = std.mem.zeroes(c.ke_node_type_builder),
        .host = s,
        .type_name = owned_name,
        .fields = .empty,
        .hooks = .empty,
        .accesses = .empty,
        .next_hook_id = c.KE_NODE_HOOK_INVALID,
    };
    b.api.handle = b;
    b.api.field = btField;
    b.api.hook = btHook;
    b.api.access = btAccess;
    return &b.api;
}

fn findHook(hooks: []const HookDecl, id: c.ke_node_hook_id) ?HookDecl {
    for (hooks) |h| if (h.id == id) return h;
    return null;
}

fn hostCommit(self_in: ?*c.ke_node_host, builder_in: ?*c.ke_node_type_builder, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const builder = builder_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const s = stateOf(self);
    const b = builderOf(builder);
    defer b.deinit();

    if (b.fields.items.len == 0) {
        E.fail(out_error, .invalid_argument, "node type declares no fields", @src());
        return false;
    }

    // -- verify: field types + compute layout -------------------------------
    var cursor: u32 = 0;
    for (b.fields.items) |*f| {
        const sz = fieldSize(f.vtype) orelse {
            E.fail(out_error, .invalid_argument, "unsupported field type (STRING/TABLE are not blittable)", @src());
            return false;
        };
        const al = fieldAlign(f.vtype);
        f.offset = alignUp(cursor, al);
        f.size = sz;
        cursor = f.offset + f.size;
    }
    const component_size = alignUp(cursor, 4);

    // -- verify: hooks map to a known phase ----------------------------------
    for (b.hooks.items) |h| {
        if (phaseFor(h.kind) == null) {
            E.fail(out_error, .invalid_argument, "hook kind has no phase mapping", @src());
            return false;
        }
    }

    // -- verify: every access's hook exists, component resolves, cap on terms --
    var per_hook_count = std.AutoHashMapUnmanaged(c.ke_node_hook_id, u32){};
    defer per_hook_count.deinit(heap.gpa);
    for (b.accesses.items) |a| {
        if (findHook(b.hooks.items, a.hook) == null) {
            E.fail(out_error, .invalid_argument, "access() references an unknown hook", @src());
            return false;
        }
        const is_self = std.mem.eql(u8, a.component_name, b.type_name);
        if (!is_self) {
            var meta: c.ke_component_meta = undefined;
            const name_z = heap.gpa.dupeZ(u8, a.component_name) catch {
                E.fail(out_error, .out_of_memory, "verification allocation failed", @src());
                return false;
            };
            defer heap.gpa.free(name_z);
            if (!s.ecs.component_lookup.?(s.ecs, name_z.ptr, &meta, null)) {
                E.fail(out_error, .not_found, "access() names a component that is not registered", @src());
                return false;
            }
        }
        const entry = per_hook_count.getOrPut(heap.gpa, a.hook) catch {
            E.fail(out_error, .out_of_memory, "verification allocation failed", @src());
            return false;
        };
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
        if (entry.value_ptr.* > c.KE_QUERY_MAX_TERMS) {
            E.fail(out_error, .invalid_argument, "hook exceeds KE_QUERY_MAX_TERMS accesses", @src());
            return false;
        }
    }

    // -- everything verified: register for real, starting with the type's own component --
    const type_name_z = heap.gpa.dupeZ(u8, b.type_name) catch {
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };
    defer heap.gpa.free(type_name_z);

    var register_err: ?*c.ke_error = null;
    const cid = s.ecs.component_register.?(s.ecs, type_name_z.ptr, component_size, &register_err);
    if (register_err != null or cid == 0) {
        if (out_error != null) out_error.* = register_err;
        return false;
    }

    // Own copy of field metadata for describe() — name re-owned as a fresh
    // null-terminated string since ke_component_field.name is a bare `const char*`.
    const fields = heap.gpa.alloc(c.ke_component_field, b.fields.items.len) catch {
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };
    for (b.fields.items, 0..) |f, i| {
        const name_z = heap.gpa.dupeZ(u8, f.name) catch {
            heap.gpa.free(fields);
            E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
            return false;
        };
        fields[i] = .{ .name = name_z.ptr, .type = f.vtype, .offset = f.offset, .size = f.size };
    }

    const dispatch_ctxs = heap.gpa.alloc(*HookDispatchCtx, b.hooks.items.len) catch {
        for (fields) |f| heap.gpa.free(std.mem.span(f.name));
        heap.gpa.free(fields);
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };

    for (b.hooks.items, 0..) |h, hi| {
        var query: c.ke_query_decl = std.mem.zeroes(c.ke_query_decl);
        var term_count: u32 = 0;
        for (b.accesses.items) |a| {
            if (a.hook != h.id) continue;
            const term_cid = if (std.mem.eql(u8, a.component_name, b.type_name)) cid else blk: {
                var meta: c.ke_component_meta = undefined;
                const name_z = heap.gpa.dupeZ(u8, a.component_name) catch unreachable; // re-verified above
                defer heap.gpa.free(name_z);
                _ = s.ecs.component_lookup.?(s.ecs, name_z.ptr, &meta, null);
                break :blk meta.cid;
            };
            query.terms[term_count] = .{ .cid = term_cid, .access = a.access };
            term_count += 1;
        }
        query.term_count = term_count;

        const dispatch = heap.gpa.create(HookDispatchCtx) catch {
            for (fields) |f| heap.gpa.free(std.mem.span(f.name));
            heap.gpa.free(fields);
            heap.gpa.free(dispatch_ctxs[0..hi]);
            E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
            return false;
        };
        dispatch.* = .{ .fn_ptr = h.fn_ptr, .ctx = h.ctx };
        dispatch_ctxs[hi] = dispatch;

        var params: c.ke_runtime_system_params = std.mem.zeroes(c.ke_runtime_system_params);
        params.name = type_name_z.ptr;
        params.phase = phaseFor(h.kind).?;
        params.queries = &query;
        params.query_count = 1;
        params.user_data = dispatch;
        params.execute = hookExecute;
        _ = s.runtime.register_system.?(s.runtime, &params, null);
    }

    const nt = heap.gpa.create(NodeType) catch {
        for (fields) |f| heap.gpa.free(std.mem.span(f.name));
        heap.gpa.free(fields);
        for (dispatch_ctxs) |d| heap.gpa.destroy(d);
        heap.gpa.free(dispatch_ctxs);
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };
    const owned_name = ownedCopy(b.type_name) catch {
        heap.gpa.destroy(nt);
        for (fields) |f| heap.gpa.free(std.mem.span(f.name));
        heap.gpa.free(fields);
        for (dispatch_ctxs) |d| heap.gpa.destroy(d);
        heap.gpa.free(dispatch_ctxs);
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };
    nt.* = .{ .name = owned_name, .cid = cid, .fields = fields, .dispatch_ctxs = dispatch_ctxs };

    s.types.put(heap.gpa, nt.name, nt) catch {
        nt.deinit();
        E.fail(out_error, .out_of_memory, "registration allocation failed", @src());
        return false;
    };
    return true;
}

fn lookupType(s: *State, type_name: [*c]const u8) ?*NodeType {
    if (type_name == null) return null;
    return s.types.get(std.mem.span(type_name));
}

fn hostSpawn(self_in: ?*c.ke_node_host, type_name: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_entity {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return c.KE_ENTITY_INVALID;
    };
    const s = stateOf(self);
    const nt = lookupType(s, type_name) orelse {
        E.fail(out_error, .not_found, "node type not registered", @src());
        return c.KE_ENTITY_INVALID;
    };
    const entity = s.ecs.entity_create.?(s.ecs);
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .general, "entity creation failed", @src());
        return c.KE_ENTITY_INVALID;
    }
    if (s.ecs.component_add.?(s.ecs, entity, nt.cid) == null) {
        s.ecs.entity_destroy.?(s.ecs, entity);
        E.fail(out_error, .general, "component attach failed", @src());
        return c.KE_ENTITY_INVALID;
    }
    return entity;
}

fn hostAttach(self_in: ?*c.ke_node_host, entity: c.ke_entity, type_name: [*c]const u8, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    const nt = lookupType(s, type_name) orelse {
        E.fail(out_error, .not_found, "node type not registered", @src());
        return false;
    };
    if (s.ecs.component_add.?(s.ecs, entity, nt.cid) == null) {
        E.fail(out_error, .general, "component attach failed", @src());
        return false;
    }
    return true;
}

fn hostDescribe(self_in: ?*c.ke_node_host, type_name: [*c]const u8, out: [*c]?*const c.ke_variant_table, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    const s = stateOf(self);
    const nt = lookupType(s, type_name) orelse {
        E.fail(out_error, .not_found, "node type not registered", @src());
        return false;
    };
    if (out == null) return true;

    // Built fresh per call and leaked deliberately: a diagnostics/tooling path,
    // called rarely, never on a hot path — matching the "describe never decides
    // semantics" contract, nothing here is freed by design because nothing here
    // is meant to be called in a loop.
    const entries = heap.gpa.alloc(c.ke_variant_table_entry, nt.fields.len) catch {
        E.fail(out_error, .out_of_memory, "describe allocation failed", @src());
        return false;
    };
    for (nt.fields, 0..) |f, i| {
        var buf: [160]u8 = undefined;
        const key = std.fmt.bufPrintZ(&buf, "{s}.type", .{std.mem.span(f.name)}) catch continue;
        const owned_key = ownedCopy(key) catch continue;
        entries[i] = .{ .key = @ptrCast(owned_key.ptr), .value = c.ke_variant_int(@intCast(f.type)) };
    }
    const table = heap.gpa.create(c.ke_variant_table) catch {
        heap.gpa.free(entries);
        E.fail(out_error, .out_of_memory, "describe allocation failed", @src());
        return false;
    };
    table.* = .{ .count = @intCast(entries.len), .entries = entries.ptr };
    out.* = table;
    return true;
}

fn vtDestroy(self_in: ?*c.ke_node_host) callconv(.c) void {
    const self = self_in orelse return;
    const s = stateOf(self);
    var it = s.types.valueIterator();
    while (it.next()) |nt| nt.*.deinit();
    s.types.deinit(heap.gpa);
    heap.gpa.destroy(s);
}

export fn ke_node_host_create(
    ecs_in: ?*c.ke_ecs,
    runtime_in: ?*c.ke_runtime,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_node_host_handle {
    const null_handle = std.mem.zeroes(c.ke_node_host_handle);
    const ecs = ecs_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };
    const runtime = runtime_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_node_host),
        .ecs = ecs,
        .runtime = runtime,
        .types = .{},
    };
    s.api.handle = s;
    s.api.begin_type = hostBeginType;
    s.api.commit = hostCommit;
    s.api.spawn = hostSpawn;
    s.api.attach = hostAttach;
    s.api.describe = hostDescribe;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

// -- tests --------------------------------------------------------------------
//
// These build a fake ke_ecs/ke_runtime vtable rather than a real flecs backend
// + scheduler — node_host.zig only ever calls through the ke_ecs/ke_runtime
// contracts (never anything flecs-specific), so a minimal fake is a truer unit
// test of that contract usage, and keeps this plugin's own tests as
// storage-agnostic as the plugin itself already is.

const testing = std.testing;

const FakeEcs = struct {
    names: [16][32]u8 = undefined,
    sizes: [16]usize = [_]usize{0} ** 16,
    count: usize = 0,
    next_entity: c.ke_entity = 1,
};
var fake_ecs_state: FakeEcs = .{};

fn fakeReset() void {
    fake_ecs_state = .{};
}

fn fakeFind(name: []const u8) ?usize {
    for (0..fake_ecs_state.count) |i| {
        if (std.mem.eql(u8, std.mem.sliceTo(&fake_ecs_state.names[i], 0), name)) return i;
    }
    return null;
}

fn fakeComponentRegister(_: ?*c.ke_ecs, name: [*c]const u8, size: usize, _: [*c][*c]c.ke_error) callconv(.c) c.ke_component_id {
    const n = std.mem.span(name);
    if (fakeFind(n)) |i| return @intCast(i + 1); // fake doesn't model the real size-mismatch rejection — see ecs_flecs.zig's own test for that
    const idx = fake_ecs_state.count;
    @memset(&fake_ecs_state.names[idx], 0);
    @memcpy(fake_ecs_state.names[idx][0..n.len], n);
    fake_ecs_state.sizes[idx] = size;
    fake_ecs_state.count += 1;
    return @intCast(idx + 1);
}

fn fakeComponentLookup(_: ?*c.ke_ecs, name: [*c]const u8, out_meta: [*c]c.ke_component_meta, _: [*c][*c]c.ke_error) callconv(.c) bool {
    const n = std.mem.span(name);
    const i = fakeFind(n) orelse return false;
    if (out_meta != null) {
        out_meta.*.cid = @intCast(i + 1);
        out_meta.*.size = fake_ecs_state.sizes[i];
        out_meta.*.fields = null;
        out_meta.*.field_count = 0;
    }
    return true;
}

fn fakeEntityCreate(_: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const e = fake_ecs_state.next_entity;
    fake_ecs_state.next_entity += 1;
    return e;
}

fn fakeEntityDestroy(_: ?*c.ke_ecs, _: c.ke_entity) callconv(.c) void {}

var fake_component_storage: u8 = 0;
fn fakeComponentAdd(_: ?*c.ke_ecs, _: c.ke_entity, _: c.ke_component_id) callconv(.c) ?*anyopaque {
    return &fake_component_storage; // non-null; nothing in these tests reads through it
}

fn fakeRegisterSystem(_: ?*c.ke_runtime, _: [*c]const c.ke_runtime_system_params, _: [*c][*c]c.ke_error) callconv(.c) c.ke_system_id {
    return 1;
}

fn makeFakeEcs() c.ke_ecs {
    var e = std.mem.zeroes(c.ke_ecs);
    e.handle = @ptrFromInt(1); // non-null sentinel; node_host.zig never dereferences it
    e.component_register = fakeComponentRegister;
    e.component_lookup = fakeComponentLookup;
    e.entity_create = fakeEntityCreate;
    e.entity_destroy = fakeEntityDestroy;
    e.component_add = fakeComponentAdd;
    return e;
}

fn makeFakeRuntime() c.ke_runtime {
    var r = std.mem.zeroes(c.ke_runtime);
    r.register_system = fakeRegisterSystem;
    return r;
}

fn testHook(_: ?*anyopaque, _: [*c]const c.ke_entity, _: [*c]const ?*anyopaque, _: usize, _: f32) callconv(.c) void {}

test "commit registers a single-field type and spawn attaches it" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const builder = host_h.ref.*.begin_type.?(host_h.ref, "TestNode", &out_error) orelse {
        try testing.expect(false);
        return;
    };
    try testing.expect(builder.*.field.?(builder, "speed", c.KE_VARIANT_FLOAT));
    try testing.expect(host_h.ref.*.commit.?(host_h.ref, builder, &out_error));
    try testing.expect(out_error == null);

    const entity = host_h.ref.*.spawn.?(host_h.ref, "TestNode", &out_error);
    try testing.expect(entity != c.KE_ENTITY_INVALID);
}

test "commit rejects a duplicate type name" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const b1 = host_h.ref.*.begin_type.?(host_h.ref, "Dup", &out_error).?;
    _ = b1.*.field.?(b1, "x", c.KE_VARIANT_INT);
    try testing.expect(host_h.ref.*.commit.?(host_h.ref, b1, &out_error));

    const b2 = host_h.ref.*.begin_type.?(host_h.ref, "Dup", &out_error);
    try testing.expect(b2 == null);
    try testing.expect(out_error != null);
}

test "commit rejects an access naming an unregistered component" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const b = host_h.ref.*.begin_type.?(host_h.ref, "Bad", &out_error).?;
    _ = b.*.field.?(b, "x", c.KE_VARIANT_INT);
    const hook = b.*.hook.?(b, c.KE_NODE_HOOK_UPDATE, testHook, null);
    try testing.expect(hook != c.KE_NODE_HOOK_INVALID);
    _ = b.*.access.?(b, hook, "not_a_real_component", c.KE_ACCESS_READ);

    try testing.expect(!host_h.ref.*.commit.?(host_h.ref, b, &out_error));
    try testing.expect(out_error != null);
}

test "commit rejects a STRING field" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const b = host_h.ref.*.begin_type.?(host_h.ref, "Stringy", &out_error).?;
    _ = b.*.field.?(b, "label", c.KE_VARIANT_STRING);

    try testing.expect(!host_h.ref.*.commit.?(host_h.ref, b, &out_error));
    try testing.expect(out_error != null);
}

test "commit resolves a self-referencing access to the type's own just-registered component" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const b = host_h.ref.*.begin_type.?(host_h.ref, "SelfRef", &out_error).?;
    _ = b.*.field.?(b, "x", c.KE_VARIANT_INT);
    const hook = b.*.hook.?(b, c.KE_NODE_HOOK_UPDATE, testHook, null);
    try testing.expect(b.*.access.?(b, hook, "SelfRef", c.KE_ACCESS_READ | c.KE_ACCESS_WRITE));

    try testing.expect(host_h.ref.*.commit.?(host_h.ref, b, &out_error));
    try testing.expect(out_error == null);
}

test "describe returns a variant table naming the declared field" {
    fakeReset();
    var ecs = makeFakeEcs();
    var runtime = makeFakeRuntime();
    const host_h = ke_node_host_create(&ecs, &runtime, null);
    defer host_h.destroy.?(host_h.ref);

    var out_error: ?*c.ke_error = null;
    const b = host_h.ref.*.begin_type.?(host_h.ref, "Described", &out_error).?;
    _ = b.*.field.?(b, "speed", c.KE_VARIANT_FLOAT);
    try testing.expect(host_h.ref.*.commit.?(host_h.ref, b, &out_error));

    var table: ?*const c.ke_variant_table = null;
    try testing.expect(host_h.ref.*.describe.?(host_h.ref, "Described", &table, &out_error));
    try testing.expect(table != null);
    try testing.expectEqual(@as(u32, 1), table.?.count);
    try testing.expectEqualStrings("speed.type", std.mem.span(table.?.entries[0].key));
}
