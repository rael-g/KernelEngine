const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");
const world_impl = @import("world.zig");
const fields_apply = @import("component_fields_apply.zig");

const E = @import("kerror").Errors(c);

/// Longest project root / scene directory path the loader tracks.
const path_max = 512;
/// Longest resolved scene path handed to fopen.
const resolved_path_max = 1024;

const res_prefix = "res://";

const Arena = struct {
    inner: std.heap.ArenaAllocator,

    fn init() Arena {
        return .{ .inner = .init(heap.gpa) };
    }

    fn allocArray(self: *Arena, comptime T: type, n: usize) ?[]T {
        if (n == 0) return &.{};
        return self.inner.allocator().alloc(T, n) catch null;
    }

    fn dupeZ(self: *Arena, src: [*c]const u8) ?[*:0]u8 {
        if (src == null) return null;
        const owned = self.inner.allocator().dupeZ(u8, std.mem.span(src)) catch return null;
        return owned.ptr;
    }

    fn deinit(self: *Arena) void {
        self.inner.deinit();
    }
};

const State = struct {
    api: c.ke_scene_loader,
    world: *c.ke_world,
    project_root: [path_max]u8,

    script_factory: c.ke_script_factory_func,
    script_ctx: ?*anyopaque,

    arena: Arena,
};

fn stateOf(self: *c.ke_scene_loader) *State {
    return @ptrCast(@alignCast(self.handle));
}

/// The world's getters return C-style pointers; narrow them to Zig optionals
/// so callers can use `orelse`.
fn ecsOf(world: *c.ke_world) ?*c.ke_ecs {
    const e = world.ecs.?(world);
    return if (e == null) null else e;
}

fn treeOf(world: *c.ke_world) ?*c.ke_scene_tree {
    const t = world.scene_tree.?(world);
    return if (t == null) null else t;
}

fn variantNull() c.ke_variant {
    return .{ .type = c.KE_VARIANT_NULL, .unnamed_0 = .{ .i = 0 } };
}
fn variantBool(b: bool) c.ke_variant {
    return .{ .type = c.KE_VARIANT_BOOL, .unnamed_0 = .{ .b = b } };
}
fn variantInt(i: i64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_INT, .unnamed_0 = .{ .i = i } };
}
fn variantFloat(f: f64) c.ke_variant {
    return .{ .type = c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = f } };
}
fn variantString(s: ?[*:0]const u8) c.ke_variant {
    return .{ .type = c.KE_VARIANT_STRING, .unnamed_0 = .{ .s = s } };
}
fn variantVec2(x: f32, y: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC2, .unnamed_0 = .{ .v2 = .{ .x = x, .y = y } } };
}
fn variantVec3(x: f32, y: f32, z: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC3, .unnamed_0 = .{ .v3 = .{ .x = x, .y = y, .z = z } } };
}
fn variantVec4(x: f32, y: f32, z: f32, w: f32) c.ke_variant {
    return .{ .type = c.KE_VARIANT_VEC4, .unnamed_0 = .{ .v4 = .{ .x = x, .y = y, .z = z, .w = w } } };
}
fn variantTable(t: *const c.ke_variant_table) c.ke_variant {
    return .{ .type = c.KE_VARIANT_TABLE, .unnamed_0 = .{ .t = t } };
}

/// Numeric arrays become vec2/vec3/vec4 by element count; anything else is null.
fn variantFromArray(arr: *c.toml_array_t) c.ke_variant {
    const n = c.toml_array_nelem(arr);
    var comps = [_]f32{ 0, 0, 0, 0 };
    const len = @min(n, @as(c_int, comps.len));
    var k: c_int = 0;
    while (k < len) : (k += 1) {
        const d = c.toml_double_at(arr, k);
        if (d.ok != 0) {
            comps[@intCast(k)] = @floatCast(d.u.d);
            continue;
        }
        const i = c.toml_int_at(arr, k);
        if (i.ok != 0) comps[@intCast(k)] = @floatFromInt(i.u.i);
    }
    if (n == 2) return variantVec2(comps[0], comps[1]);
    if (n == 3) return variantVec3(comps[0], comps[1], comps[2]);
    if (n >= 4) return variantVec4(comps[0], comps[1], comps[2], comps[3]);
    return variantNull();
}

/// Inline TOML tables convert recursively; strings and nested tables are copied
/// into the arena so they outlive the parsed TOML tree.
fn variantFromTable(s: *State, tbl: *c.toml_table_t) c.ke_variant {
    const n: usize = @intCast(c.toml_table_nkval(tbl) + c.toml_table_ntab(tbl) + c.toml_table_narr(tbl));
    const entries = s.arena.allocArray(c.ke_variant_table_entry, n) orelse return variantNull();
    const vtbl_mem = s.arena.allocArray(c.ke_variant_table, 1) orelse return variantNull();

    var count: usize = 0;
    var k: c_int = 0;
    while (count < n) : (k += 1) {
        const key = c.toml_key_in(tbl, k) orelse break;
        entries[count] = .{
            .key = s.arena.dupeZ(key),
            .value = readVarIn(s, tbl, key),
        };
        count += 1;
    }

    vtbl_mem[0] = .{ .count = @intCast(count), .entries = entries.ptr };
    return variantTable(&vtbl_mem[0]);
}

/// Reads the value at `key` through whichever typed accessor matches.
fn readVarIn(s: *State, tbl: *c.toml_table_t, key: [*c]const u8) c.ke_variant {
    const ds = c.toml_string_in(tbl, key);
    if (ds.ok != 0) {
        const v = variantString(s.arena.dupeZ(ds.u.s));
        std.c.free(ds.u.s);
        return v;
    }
    const di = c.toml_int_in(tbl, key);
    if (di.ok != 0) return variantInt(di.u.i);
    const dd = c.toml_double_in(tbl, key);
    if (dd.ok != 0) return variantFloat(dd.u.d);
    const db = c.toml_bool_in(tbl, key);
    if (db.ok != 0) return variantBool(db.u.b != 0);
    if (c.toml_array_in(tbl, key)) |arr| return variantFromArray(arr);
    if (c.toml_table_in(tbl, key)) |sub| return variantFromTable(s, sub);
    return variantNull();
}

fn pathDirname(path: []const u8, out: []u8) []const u8 {
    const idx = std.mem.lastIndexOfAny(u8, path, "/\\") orelse {
        out[0] = '.';
        out[1] = 0;
        return out[0..1];
    };
    const n = @min(idx, out.len - 1);
    @memcpy(out[0..n], path[0..n]);
    out[n] = 0;
    return out[0..n];
}

fn writeJoined(out: []u8, parts: []const []const u8) void {
    var i: usize = 0;
    for (parts) |part| {
        for (part) |ch| {
            if (i >= out.len - 1) break;
            out[i] = ch;
            i += 1;
        }
    }
    out[i] = 0;
}

/// res:// resolves against the project root; absolute paths pass through;
/// everything else is relative to the referring scene's directory.
fn resolvePath(s: *const State, base_dir: []const u8, ref: []const u8, out: []u8) void {
    if (std.mem.startsWith(u8, ref, res_prefix)) {
        const rest = ref[res_prefix.len..];
        const root = std.mem.sliceTo(&s.project_root, 0);
        if (root.len != 0) {
            writeJoined(out, &.{ root, "/", rest });
        } else {
            writeJoined(out, &.{rest});
        }
        return;
    }
    const is_absolute = ref.len > 0 and (ref[0] == '/' or (ref.len > 1 and ref[1] == ':'));
    if (is_absolute) {
        writeJoined(out, &.{ref});
        return;
    }
    writeJoined(out, &.{ base_dir, "/", ref });
}

const type_name_max = 128;

/// Rewrites a node type name into the one spelling the engine resolves by:
/// `+` becomes `.`, and each word boundary inside an identifier becomes `_`,
/// so `Pong.Ball`, `Pong+Ball` and `pong.ball` all name the same type. Returns
/// null when the result would not fit, leaving the caller to reject the name
/// rather than dispatch a truncated one.
fn normalizeTypeName(name: [*c]const u8, out: *[type_name_max]u8) ?[*:0]const u8 {
    if (name == null) return null;
    const src = std.mem.sliceTo(name, 0);
    var len: usize = 0;

    for (src, 0..) |ch, i| {
        if (ch == '+') {
            if (len + 1 >= out.len) return null;
            out[len] = '.';
            len += 1;
            continue;
        }
        if (std.ascii.isUpper(ch)) {
            const raw_prev: u8 = if (i > 0) src[i - 1] else '.';
            const prev: u8 = if (raw_prev == '+') '.' else raw_prev;
            const next_is_lower = i + 1 < src.len and std.ascii.isLower(src[i + 1]);
            const starts_word = prev != '.' and prev != '_' and !std.ascii.isDigit(prev) and
                (!std.ascii.isUpper(prev) or next_is_lower);
            if (starts_word) {
                if (len + 1 >= out.len) return null;
                out[len] = '_';
                len += 1;
            }
            if (len + 1 >= out.len) return null;
            out[len] = std.ascii.toLower(ch);
            len += 1;
            continue;
        }
        if (len + 1 >= out.len) return null;
        out[len] = ch;
        len += 1;
    }

    out[len] = 0;
    return @ptrCast(out);
}

fn dispatchScript(s: *State, entity: c.ke_entity, type_name: [*c]const u8) void {
    const factory = s.script_factory orelse return;
    var buf: [type_name_max]u8 = undefined;
    const resolved = normalizeTypeName(type_name, &buf) orelse return;
    _ = factory(s.script_ctx, entity, resolved, null);
}

fn tableEntryCount(tbl: *c.toml_table_t) usize {
    return @intCast(c.toml_table_nkval(tbl) + c.toml_table_narr(tbl) + c.toml_table_ntab(tbl));
}

/// Builds an arena-backed entry list for every key in `tbl`.
fn buildEntries(s: *State, tbl: *c.toml_table_t) ?[]c.ke_variant_table_entry {
    const n = tableEntryCount(tbl);
    if (n == 0) return null;
    const entries = s.arena.allocArray(c.ke_variant_table_entry, n) orelse return null;
    var count: usize = 0;
    var k: c_int = 0;
    while (count < n) : (k += 1) {
        const key = c.toml_key_in(tbl, k) orelse break;
        entries[count] = .{
            .key = s.arena.dupeZ(key),
            .value = readVarIn(s, tbl, key),
        };
        count += 1;
    }
    return entries[0..count];
}

fn log(world: *c.ke_world, level: c_int, comptime fmt: []const u8, args: anytype) void {
    const lg = world_impl.loggerOf(world) orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch return;
    var ev = c.ke_log_event{ .level = level, .tag = "scene.loader", .message = msg.ptr };
    if (lg.log) |f| f(lg, &ev);
}

fn warn(world: *c.ke_world, comptime fmt: []const u8, args: anytype) void {
    log(world, c.KE_LOG_LEVEL_WARNING, fmt, args);
}

/// Reports a structural fault and fails the load.
fn structural(
    world: *c.ke_world,
    out_error: [*c][*c]c.ke_error,
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, fmt, args) catch "scene is not loadable";
    log(world, c.KE_LOG_LEVEL_ERROR, "{s}", .{msg});
    E.fail(out_error, .invalid_argument, msg, @src());
}

fn applyComponentBlock(
    s: *State,
    entity: c.ke_entity,
    comp_name: [*c]const u8,
    comp_tbl: *c.toml_table_t,
    out_error: [*c][*c]c.ke_error,
) bool {
    const world = s.world;
    const e = ecsOf(world) orelse {
        structural(world, out_error, "world has no ecs", .{});
        return false;
    };

    var meta: c.ke_component_meta = undefined;
    if (!e.component_lookup.?(e, comp_name, &meta, null)) {
        structural(world, out_error, "scene names component '{s}', which no module registered", .{comp_name});
        return false;
    }

    var field_count: u32 = 0;
    const fields = world.get_component_fields.?(world, meta.cid, &field_count);
    const apply_fn = world.get_component_apply.?(world, meta.cid);
    if (fields == null and apply_fn == null) {
        structural(world, out_error, "component '{s}' has no field mapping registered", .{comp_name});
        return false;
    }

    const existing = e.component_get.?(e, entity, meta.cid);
    const comp = e.component_add.?(e, entity, meta.cid) orelse {
        structural(world, out_error, "component '{s}' could not be added to the entity", .{comp_name});
        return false;
    };
    if (existing == null) {
        const bytes: [*]u8 = @ptrCast(comp);
        @memset(bytes[0..meta.size], 0);
        if (fields) |f| fields_apply.seedDefaults(comp, f, field_count);
    }

    const entries = buildEntries(s, comp_tbl) orelse {
        structural(world, out_error, "component '{s}' block could not be read", .{comp_name});
        return false;
    };

    if (fields != null)
        fields_apply.apply(comp, entries.ptr, @intCast(entries.len), fields, field_count);
    if (apply_fn) |f| {
        if (!f(comp, entries.ptr, @intCast(entries.len))) {
            structural(world, out_error, "component '{s}' was given a value it cannot hold", .{comp_name});
            return false;
        }
    }

    for (entries) |*entry| {
        if (entry.consumed) continue;
        structural(world, out_error, "component '{s}' has no field '{s}'", .{ comp_name, entry.key });
        return false;
    }
    return true;
}

/// A connection is authored as an array of tables, so a plain table by that name
/// only ever reaches here written in the singular. Wiring is not something a file
/// may ask for and not get, so the spelling is corrected rather than skipped.
fn reservedBlockMiswritten(key: [*c]const u8) bool {
    return std.mem.eql(u8, std.mem.span(key), "connect");
}

/// A retired block shape, and what to write instead.
fn retiredBlock(key: [*c]const u8) ?[]const u8 {
    const k = std.mem.span(key);
    if (std.mem.eql(u8, k, "components")) return "write [entity.<component>] directly";
    if (std.mem.eql(u8, k, "properties")) return "write the component the value belongs to";
    return null;
}

/// Components the scene tree owns, which a scene may not author.
fn internalComponent(key: [*c]const u8) bool {
    const k = std.mem.span(key);
    return std.mem.eql(u8, k, c.KE_COMPONENT_NAME_NAME) or
        std.mem.eql(u8, k, c.KE_COMPONENT_NAME_HIERARCHY);
}

/// Applies every `[entity.<component_name>]` block on one table.
fn applyComponentBlocks(
    s: *State,
    entity: c.ke_entity,
    tbl: *c.toml_table_t,
    out_error: [*c][*c]c.ke_error,
) bool {
    var i: c_int = 0;
    while (true) : (i += 1) {
        const key = c.toml_key_in(tbl, i) orelse break;
        const block = c.toml_table_in(tbl, key) orelse continue;
        if (retiredBlock(key)) |advice| {
            structural(s.world, out_error, "[entity.{s}] is no longer read; {s}", .{ key, advice });
            return false;
        }
        if (reservedBlockMiswritten(key)) {
            structural(s.world, out_error, "[entity.connect] declares nothing; a connection is written [[entity.connect]]", .{});
            return false;
        }
        if (internalComponent(key)) {
            structural(s.world, out_error, "component '{s}' is the scene tree's own and cannot be authored", .{key});
            return false;
        }
        if (!applyComponentBlock(s, entity, key, block, out_error)) return false;
    }
    return true;
}

/// Wires the `[[entity.connect]]` blocks one entity declares.
///
/// Resolved in a pass after every entity in the file exists, because a listener
/// is as often declared below the emitter as above it, and requiring one order
/// would make the wiring depend on file layout rather than on what it says.
/// Wires the connect blocks one entity declares. A connection that resolves to
/// nothing fails the load.
fn applyConnections(
    s: *State,
    source: c.ke_entity,
    entity_tbl: *c.toml_table_t,
    names: *const NameMap,
    out_error: [*c][*c]c.ke_error,
) bool {
    const arr = c.toml_array_in(entity_tbl, "connect") orelse return true;
    const world = s.world;

    const bus = world_impl.signalBusOf(world) orelse {
        structural(world, out_error, "scene declares signal connections but the world has no signal bus", .{});
        return false;
    };

    const n = c.toml_array_nelem(arr);
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        const t = c.toml_table_at(arr, i) orelse continue;

        const signal_d = c.toml_string_in(t, "signal");
        defer if (signal_d.ok != 0) std.c.free(signal_d.u.s);
        const target_d = c.toml_string_in(t, "target");
        defer if (target_d.ok != 0) std.c.free(target_d.u.s);

        if (signal_d.ok == 0 or target_d.ok == 0) {
            structural(world, out_error, "a connect block needs both a signal and a target", .{});
            return false;
        }

        const target = names.get(std.mem.span(target_d.u.s)) orelse {
            structural(world, out_error, "connect targets '{s}', which this scene declares no entity for", .{target_d.u.s});
            return false;
        };

        var handler: u32 = 0;
        const handler_d = c.toml_int_in(t, "handler");
        if (handler_d.ok != 0) handler = @intCast(handler_d.u.i);

        var signal_id: u32 = 0;
        if (!bus.signal_id.?(bus, signal_d.u.s, c.KE_SIGNAL_PAYLOAD_SIZE_UNKNOWN, &signal_id, null)) {
            structural(world, out_error, "could not resolve signal '{s}'", .{signal_d.u.s});
            return false;
        }
        if (!bus.connect.?(bus, source, signal_id, target, handler, null)) {
            structural(world, out_error, "could not connect signal '{s}'", .{signal_d.u.s});
            return false;
        }
        log(world, c.KE_LOG_LEVEL_INFO, "connected '{s}' from entity {d} to entity {d}", .{ signal_d.u.s, source, target });
    }
    return true;
}

/// Name -> entity map for resolving `parent = "..."` back-references within one
/// scene file. Grows on demand: a scene may declare any number of named
/// entities, and silently dropping late ones would break their children.
const NameMap = struct {
    const Entry = struct { name: [*:0]u8, entity: c.ke_entity };

    items: ?[*]Entry = null,
    count: u32 = 0,
    capacity: u32 = 0,
    arena: *Arena,

    const initial_capacity: u32 = 16;

    fn put(self: *NameMap, name: [*c]const u8, entity: c.ke_entity) void {
        if (self.count == self.capacity) {
            const cap = if (self.capacity != 0) self.capacity * 2 else initial_capacity;
            const buf = heap.gpa.alloc(Entry, cap) catch return;
            if (self.items) |old| {
                @memcpy(buf[0..self.count], old[0..self.count]);
                heap.gpa.free(old[0..self.capacity]);
            }
            self.items = buf.ptr;
            self.capacity = cap;
        }
        const owned = self.arena.dupeZ(name) orelse return;
        self.items.?[self.count] = .{ .name = owned, .entity = entity };
        self.count += 1;
    }

    fn get(self: *const NameMap, name: []const u8) ?c.ke_entity {
        const items = self.items orelse return null;
        for (items[0..self.count]) |entry| {
            if (std.mem.eql(u8, std.mem.span(entry.name), name)) return entry.entity;
        }
        return null;
    }

    fn deinit(self: *NameMap) void {
        if (self.items) |items| heap.gpa.free(items[0..self.capacity]);
        self.items = null;
    }
};

const ProcessArgs = struct {
    base_dir: []const u8,
    entity_tbl: *c.toml_table_t,
    names: *NameMap,
    attach_parent_override: c.ke_entity,
    override_name: ?[*:0]const u8,
    override_outer: ?*c.toml_table_t,
};

fn processEntity(
    s: *State,
    args: ProcessArgs,
    out_entity: *c.ke_entity,
    out_error: [*c][*c]c.ke_error,
) bool {
    const name_d = c.toml_string_in(args.entity_tbl, "name");
    defer if (name_d.ok != 0) std.c.free(name_d.u.s);

    if (name_d.ok == 0 and args.override_name == null) {
        E.fail(out_error, .invalid_argument, "entity missing name", @src());
        return false;
    }
    const effective_name: [*c]const u8 = if (args.override_name) |n| n else name_d.u.s;

    const world = s.world;
    const tree = treeOf(world) orelse {
        E.fail(out_error, .not_initialized, "world has no scene tree", @src());
        return false;
    };
    var parent = if (args.attach_parent_override != c.KE_ENTITY_INVALID)
        args.attach_parent_override
    else
        tree.root.?(tree);

    const pn = c.toml_string_in(args.entity_tbl, "parent");
    if (pn.ok != 0) {
        const found = args.names.get(std.mem.span(pn.u.s));
        std.c.free(pn.u.s);
        parent = found orelse {
            E.fail(out_error, .not_found, "parent entity not found", @src());
            return false;
        };
    }

    const scene_ref = c.toml_string_in(args.entity_tbl, "scene");
    if (scene_ref.ok != 0) {
        var resolved: [resolved_path_max]u8 = undefined;
        resolvePath(s, args.base_dir, std.mem.span(scene_ref.u.s), &resolved);
        std.c.free(scene_ref.u.s);

        var nested_root: c.ke_entity = c.KE_ENTITY_INVALID;
        if (!loadSceneRecursive(
            s,
            @ptrCast(&resolved),
            parent,
            effective_name,
            args.entity_tbl,
            &nested_root,
            out_error,
        )) return false;

        if (name_d.ok != 0) args.names.put(name_d.u.s, nested_root);
        out_entity.* = nested_root;
        return true;
    }

    const entity = tree.create_node.?(tree, effective_name, parent, null, out_error);
    if (entity == c.KE_ENTITY_INVALID) {
        E.fail(out_error, .out_of_memory, "failed to create node", @src());
        return false;
    }

    if (!applyComponentBlocks(s, entity, args.entity_tbl, out_error)) return false;
    if (args.override_outer) |outer| {
        if (!applyComponentBlocks(s, entity, outer, out_error)) return false;
    }

    const type_d = c.toml_string_in(args.entity_tbl, "type");
    if (type_d.ok != 0) {
        dispatchScript(s, entity, type_d.u.s);
        std.c.free(type_d.u.s);
    }

    if (args.override_outer) |outer| {
        const outer_type = c.toml_string_in(outer, "type");
        if (outer_type.ok != 0) {
            dispatchScript(s, entity, outer_type.u.s);
            std.c.free(outer_type.u.s);
        }
    }

    if (name_d.ok != 0) args.names.put(name_d.u.s, entity);
    out_entity.* = entity;
    return true;
}

fn loadSceneRecursive(
    s: *State,
    path: [*:0]const u8,
    attach_parent: c.ke_entity,
    override_name: ?[*:0]const u8,
    override_outer: ?*c.toml_table_t,
    out_root: ?*c.ke_entity,
    out_error: [*c][*c]c.ke_error,
) bool {
    const fp = std.c.fopen(path, "rb") orelse {
        E.fail(out_error, .not_found, "scene file not found", @src());
        return false;
    };
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse_file(@ptrCast(@alignCast(fp)), &errbuf, errbuf.len);
    _ = std.c.fclose(fp);
    if (root == null) {
        E.fail(out_error, .io, "failed to parse scene file", @src());
        return false;
    }
    defer c.toml_free(root);

    var base_buf: [path_max]u8 = undefined;
    const base_dir = pathDirname(std.mem.span(path), &base_buf);

    const entities = c.toml_array_in(root, "entity") orelse {
        if (out_root) |r| r.* = c.KE_ENTITY_INVALID;
        return true;
    };

    var names: NameMap = .{ .arena = &s.arena };
    defer names.deinit();

    var first_root: c.ke_entity = c.KE_ENTITY_INVALID;
    const n = c.toml_array_nelem(entities);

    const created = s.arena.allocArray(c.ke_entity, @intCast(n));

    var is_first = true;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        const et = c.toml_table_at(entities, i) orelse continue;
        var ent: c.ke_entity = c.KE_ENTITY_INVALID;

        const args: ProcessArgs = if (is_first) .{
            .base_dir = base_dir,
            .entity_tbl = et,
            .names = &names,
            .attach_parent_override = attach_parent,
            .override_name = override_name,
            .override_outer = override_outer,
        } else .{
            .base_dir = base_dir,
            .entity_tbl = et,
            .names = &names,
            .attach_parent_override = c.KE_ENTITY_INVALID,
            .override_name = null,
            .override_outer = null,
        };

        if (!processEntity(s, args, &ent, out_error)) return false;
        if (created) |slots| slots[@intCast(i)] = ent;
        if (is_first) {
            first_root = ent;
            is_first = false;
        }
    }

    if (created) |slots| {
        var j: c_int = 0;
        while (j < n) : (j += 1) {
            const et = c.toml_table_at(entities, j) orelse continue;
            if (!applyConnections(s, slots[@intCast(j)], et, &names, out_error)) return false;
        }
    }

    if (out_root) |r| r.* = first_root;
    return true;
}

fn vtLoad(
    self_in: ?*c.ke_scene_loader,
    path: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or path == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    return loadSceneRecursive(stateOf(self), path, c.KE_ENTITY_INVALID, null, null, null, out_error);
}

fn vtRegisterScriptFactory(
    self_in: ?*c.ke_scene_loader,
    factory: c.ke_script_factory_func,
    ctx: ?*anyopaque,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    const self = self_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    };
    if (self.handle == null or factory == null) {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return false;
    }
    const s = stateOf(self);
    s.script_factory = factory;
    s.script_ctx = ctx;
    return true;
}

fn vtDestroy(self_in: ?*c.ke_scene_loader) callconv(.c) void {
    const self = self_in orelse return;
    if (self.handle == null) return;
    const s = stateOf(self);
    s.arena.deinit();
    heap.gpa.destroy(s);
}

export fn ke_scene_loader_create(
    world_in: ?*c.ke_world,
    project_root: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_scene_loader_handle {
    const null_handle = std.mem.zeroes(c.ke_scene_loader_handle);
    const world = world_in orelse {
        E.fail(out_error, .invalid_argument, "invalid argument", @src());
        return null_handle;
    };

    const s = heap.gpa.create(State) catch {
        E.fail(out_error, .out_of_memory, "state allocation failed", @src());
        return null_handle;
    };
    s.* = .{
        .api = std.mem.zeroes(c.ke_scene_loader),
        .world = world,
        .project_root = [_]u8{0} ** path_max,
        .script_factory = null,
        .script_ctx = null,
        .arena = .init(),
    };

    if (project_root != null) {
        const root = std.mem.span(project_root);
        const n = @min(root.len, s.project_root.len - 1);
        @memcpy(s.project_root[0..n], root[0..n]);
        s.project_root[n] = 0;
    }

    s.api.handle = s;
    s.api.load = vtLoad;
    s.api.register_script_factory = vtRegisterScriptFactory;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}

const testing = std.testing;

const signal_bus_impl = @import("signal_bus.zig");

const rc = @cImport({
    @cInclude("kernel_engine/render/component_fields.h");
    @cInclude("kernel_engine/render/ui/component_fields.h");
    @cInclude("kernel_engine/audio/component_fields.h");
    @cInclude("kernel_engine/physics/component_fields.h");
});

const fake_max_components = 32;
const fake_max_entities = 128;

const FakeComponent = struct {
    name: []const u8,
    size: usize,
};

const FakeEcs = struct {
    vtable: c.ke_ecs,
    arena: std.heap.ArenaAllocator,
    components: [fake_max_components]FakeComponent,
    component_count: usize,
    alive: [fake_max_entities]bool,
    storage: [fake_max_entities][fake_max_components]?[*]u8,
    next_entity: c.ke_entity,
};

fn fakeEcsOf(self: ?*c.ke_ecs) *FakeEcs {
    return @ptrCast(@alignCast(self.?.handle));
}

fn fakeSlot(f: *FakeEcs, entity: c.ke_entity, cid: c.ke_component_id) ?*?[*]u8 {
    if (entity == c.KE_ENTITY_INVALID or entity > fake_max_entities) return null;
    const row = entity - 1;
    if (!f.alive[row]) return null;
    if (cid == 0 or cid > f.component_count) return null;
    return &f.storage[row][cid - 1];
}

fn fakeEntityCreate(self: ?*c.ke_ecs) callconv(.c) c.ke_entity {
    const f = fakeEcsOf(self);
    if (f.next_entity >= fake_max_entities) return c.KE_ENTITY_INVALID;
    f.next_entity += 1;
    f.alive[f.next_entity - 1] = true;
    return f.next_entity;
}

fn fakeEntityDestroy(self: ?*c.ke_ecs, entity: c.ke_entity) callconv(.c) void {
    const f = fakeEcsOf(self);
    if (entity == c.KE_ENTITY_INVALID or entity > fake_max_entities) return;
    const row = entity - 1;
    f.alive[row] = false;
    for (&f.storage[row]) |*cell| cell.* = null;
}

fn fakeComponentRegister(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    element_size: usize,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) c.ke_component_id {
    _ = out_error;
    const f = fakeEcsOf(self);
    const wanted = std.mem.span(name);
    for (f.components[0..f.component_count], 0..) |comp, i| {
        if (std.mem.eql(u8, comp.name, wanted)) return @intCast(i + 1);
    }
    if (f.component_count >= fake_max_components) return 0;
    f.components[f.component_count] = .{ .name = wanted, .size = element_size };
    f.component_count += 1;
    return @intCast(f.component_count);
}

fn fakeComponentLookup(
    self: ?*c.ke_ecs,
    name: [*c]const u8,
    out_meta: [*c]c.ke_component_meta,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    _ = out_error;
    const f = fakeEcsOf(self);
    const wanted = std.mem.span(name);
    for (f.components[0..f.component_count], 0..) |comp, i| {
        if (!std.mem.eql(u8, comp.name, wanted)) continue;
        if (out_meta != null) {
            out_meta.* = .{
                .cid = @intCast(i + 1),
                .size = comp.size,
                .fields = null,
                .field_count = 0,
            };
        }
        return true;
    }
    return false;
}

fn fakeComponentAdd(
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) ?*anyopaque {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return null;
    if (slot.*) |existing| return existing;
    const size = f.components[component - 1].size;
    const block = f.arena.allocator().alignedAlloc(u8, .of(u64), @max(size, 1)) catch return null;
    @memset(block, 0);
    slot.* = block.ptr;
    return block.ptr;
}

fn fakeComponentRemove(
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) void {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return;
    slot.* = null;
}

fn fakeComponentGet(
    self: ?*c.ke_ecs,
    entity: c.ke_entity,
    component: c.ke_component_id,
) callconv(.c) ?*anyopaque {
    const f = fakeEcsOf(self);
    const slot = fakeSlot(f, entity, component) orelse return null;
    return slot.*;
}

fn fakeComponentSize(self: ?*c.ke_ecs, cid: c.ke_component_id) callconv(.c) usize {
    const f = fakeEcsOf(self);
    if (cid == 0 or cid > f.component_count) return 0;
    return f.components[cid - 1].size;
}

fn generatedFields(table: anytype) [*c]const c.ke_component_field {
    return @ptrCast(@alignCast(table));
}

const DemoComponent = extern struct {
    fov: f32,
    mode: i32,
};

fn demoApply(ptr: ?*anyopaque, e: [*c]c.ke_variant_table_entry, n: u32) callconv(.c) bool {
    const d: *DemoComponent = @ptrCast(@alignCast(ptr));
    if (n == 0) return true;
    for (e[0..n]) |*entry| {
        if (entry.key == null) continue;
        const key = std.mem.span(entry.key);
        if (std.mem.eql(u8, key, "fov")) {
            if (entry.value.type == c.KE_VARIANT_FLOAT) {
                d.fov = @floatCast(entry.value.unnamed_0.f);
            } else if (entry.value.type == c.KE_VARIANT_INT) {
                d.fov = @floatFromInt(entry.value.unnamed_0.i);
            }
            entry.consumed = true;
        } else if (std.mem.eql(u8, key, "mode") and entry.value.type == c.KE_VARIANT_INT) {
            d.mode = @intCast(entry.value.unnamed_0.i);
            entry.consumed = true;
        }
    }
    return true;
}

const ScriptSpy = struct {
    calls: i32 = 0,
    last_type: [64]u8 = [_]u8{0} ** 64,
    last_entity: c.ke_entity = c.KE_ENTITY_INVALID,
};

fn spyFactory(
    ctx: ?*anyopaque,
    entity: c.ke_entity,
    type_name: [*c]const u8,
    out_error: [*c][*c]c.ke_error,
) callconv(.c) bool {
    _ = out_error;
    const spy: *ScriptSpy = @ptrCast(@alignCast(ctx.?));
    spy.calls += 1;
    spy.last_entity = entity;
    const name = std.mem.span(type_name);
    const n = @min(name.len, spy.last_type.len - 1);
    @memcpy(spy.last_type[0..n], name[0..n]);
    spy.last_type[n] = 0;
    return true;
}

const TempScene = struct {
    tmp: std.testing.TmpDir,
    path_buf: [std.fs.max_path_bytes]u8,

    fn init() TempScene {
        return .{ .tmp = std.testing.tmpDir(.{}), .path_buf = undefined };
    }

    fn put(self: *TempScene, name: []const u8, contents: []const u8) !void {
        try self.tmp.dir.writeFile(testing.io, .{ .sub_path = name, .data = contents });
    }

    fn cPath(self: *TempScene, name: []const u8) ![*:0]const u8 {
        const full = try std.fmt.bufPrint(&self.path_buf, ".zig-cache/tmp/{s}/{s}", .{ self.tmp.sub_path, name });
        self.path_buf[full.len] = 0;
        return @ptrCast(&self.path_buf);
    }

    fn deinit(self: *TempScene) void {
        self.tmp.cleanup();
    }
};

const Fixture = struct {
    ecs: FakeEcs,
    runtime: c.ke_runtime,
    tree_h: c.ke_scene_tree_handle,
    bus_h: c.ke_signal_bus_handle,
    world_h: c.ke_world_handle,
    loader_h: c.ke_scene_loader_handle,

    fn init(self: *Fixture) !void {
        return self.initEx(true);
    }

    fn initEx(self: *Fixture, with_signal_bus: bool) !void {
        self.ecs.arena = std.heap.ArenaAllocator.init(testing.allocator);
        self.ecs.component_count = 0;
        self.ecs.next_entity = 0;
        @memset(&self.ecs.alive, false);
        for (&self.ecs.storage) |*row| @memset(row, null);
        self.ecs.vtable = std.mem.zeroes(c.ke_ecs);
        self.ecs.vtable.handle = &self.ecs;
        self.ecs.vtable.entity_create = fakeEntityCreate;
        self.ecs.vtable.entity_destroy = fakeEntityDestroy;
        self.ecs.vtable.component_register = fakeComponentRegister;
        self.ecs.vtable.component_lookup = fakeComponentLookup;
        self.ecs.vtable.component_add = fakeComponentAdd;
        self.ecs.vtable.component_remove = fakeComponentRemove;
        self.ecs.vtable.component_get = fakeComponentGet;
        self.ecs.vtable.component_size = fakeComponentSize;

        self.runtime = std.mem.zeroes(c.ke_runtime);

        self.tree_h = c.ke_scene_tree_create(&self.ecs.vtable, null, null);
        try testing.expect(self.tree_h.ref != null);

        self.bus_h = std.mem.zeroes(c.ke_signal_bus_handle);
        if (with_signal_bus) {
            self.bus_h = signal_bus_impl.ke_signal_bus_create(null, null);
            try testing.expect(self.bus_h.ref != null);
        }

        var params = std.mem.zeroes(c.ke_world_params);
        params.ecs = &self.ecs.vtable;
        params.runtime = &self.runtime;
        params.scene_tree = self.tree_h.ref;
        params.signal_bus = self.bus_h.ref;
        self.world_h = c.ke_world_create(&params, null);
        try testing.expect(self.world_h.ref != null);

        self.describe(rc.KE_COMPONENT_NAME_CAMERA, @sizeOf(rc.ke_camera_component), generatedFields(&rc.ke_camera_component_fields), rc.ke_camera_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, @sizeOf(rc.ke_directional_light_component), generatedFields(&rc.ke_directional_light_component_fields), rc.ke_directional_light_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(rc.ke_point_light_component), generatedFields(&rc.ke_point_light_component_fields), rc.ke_point_light_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(rc.ke_spot_light_component), generatedFields(&rc.ke_spot_light_component_fields), rc.ke_spot_light_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_MESH, @sizeOf(rc.ke_mesh_component), generatedFields(&rc.ke_mesh_component_fields), rc.ke_mesh_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_SPRITE_2D, @sizeOf(rc.ke_sprite2d_component), generatedFields(&rc.ke_sprite2d_component_fields), rc.ke_sprite2d_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_LABEL, @sizeOf(rc.ke_label_component), generatedFields(&rc.ke_label_component_fields), rc.ke_label_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_AUDIO_PLAYER, @sizeOf(rc.ke_audio_player_component), generatedFields(&rc.ke_audio_player_component_fields), rc.ke_audio_player_component_fields.len);
        self.describe(rc.KE_COMPONENT_NAME_COLLIDER_2D, @sizeOf(rc.ke_collider2d_component), generatedFields(&rc.ke_collider2d_component_fields), rc.ke_collider2d_component_fields.len);

        self.loader_h = ke_scene_loader_create(self.world_h.ref, null, null);
        try testing.expect(self.loader_h.ref != null);
    }

    fn describe(
        self: *Fixture,
        name: [*c]const u8,
        size: usize,
        fields: [*c]const c.ke_component_field,
        field_count: usize,
    ) void {
        const e = &self.ecs.vtable;
        const cid = e.component_register.?(e, name, size, null);
        const w = self.world_h.ref.?;
        _ = w.*.register_component_fields.?(w, cid, fields, @intCast(field_count), null);
    }

    fn deinit(self: *Fixture) void {
        if (self.loader_h.destroy) |d| d(self.loader_h.ref);
        if (self.world_h.destroy) |d| d(self.world_h.ref);
        if (self.bus_h.destroy) |d| d(self.bus_h.ref);
        if (self.tree_h.destroy) |d| d(self.tree_h.ref);
        self.ecs.arena.deinit();
    }

    fn loader(self: *Fixture) *c.ke_scene_loader {
        return self.loader_h.ref.?;
    }

    fn load(self: *Fixture, path: [*:0]const u8) bool {
        const l = self.loader();
        return l.load.?(l, path, null);
    }

    fn loadReporting(self: *Fixture, path: [*:0]const u8, out_error: *[*c]c.ke_error) bool {
        const l = self.loader();
        return l.load.?(l, path, out_error);
    }

    fn find(self: *Fixture, path: [*c]const u8) c.ke_entity {
        const t = self.tree_h.ref.?;
        return t.*.find_node.?(t, path, null);
    }

    fn comp(self: *Fixture, comptime T: type, name: [*c]const u8, entity: c.ke_entity) ?*T {
        var meta: c.ke_component_meta = undefined;
        if (!fakeComponentLookup(&self.ecs.vtable, name, &meta, null)) return null;
        return @ptrCast(@alignCast(fakeComponentGet(&self.ecs.vtable, entity, meta.cid)));
    }

    fn bus(self: *Fixture) *c.ke_signal_bus {
        return self.bus_h.ref.?;
    }

    fn declaredSignal(self: *Fixture, name: [*c]const u8) !u32 {
        const b = self.bus();
        var id: u32 = 0;
        try testing.expect(b.signal_id.?(b, name, 0, &id, null));
        return id;
    }

    fn emitFrom(self: *Fixture, source: c.ke_entity, signal: u32) !void {
        const b = self.bus();
        try testing.expect(b.emit.?(b, source, signal, null, 0, null));
    }

    fn delivered(self: *Fixture) []const c.ke_signal_delivery {
        const b = self.bus();
        var count: u32 = 0;
        const list = b.deliveries.?(b, &count);
        if (count == 0) return &.{};
        return list[0..count];
    }
};

test "a scene that declares no entity still loads" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml", "[scene]\nname = \"empty\"\n");

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
}

test "a scene file that is not there fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    try testing.expect(!f.load("no_such_file_anywhere.scene.toml"));
}

test "a named entity reaches the tree" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Player"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    try testing.expect(f.find("Player") != c.KE_ENTITY_INVALID);
}

test "parent names an entity declared earlier in the same file" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "World"
        \\
        \\[[entity]]
        \\name = "Child"
        \\parent = "World"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    try testing.expect(f.find("World/Child") != c.KE_ENTITY_INVALID);
}

test "a transform position reaches the component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "X"
        \\[entity.transform]
        \\position = [1.0, 2.0, 3.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("X");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const t = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, e) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, 1.0), t.position.x);
    try testing.expectEqual(@as(f32, 2.0), t.position.y);
    try testing.expectEqual(@as(f32, 3.0), t.position.z);
}

test "a two dimensional rotation authored in degrees reaches the component as radians" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Flat"
        \\[entity.transform2d]
        \\position = [1.0, 2.0]
        \\rotation = 90.0
        \\scale    = [3.0, 4.0]
        \\depth    = 5.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Flat");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const t = f.comp(c.ke_transform2d_component, c.KE_COMPONENT_NAME_TRANSFORM_2D, e) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, 1.0), t.position.x);
    try testing.expectEqual(@as(f32, 2.0), t.position.y);
    try testing.expectApproxEqAbs(@as(f32, 1.57079633), t.rotation, 1e-5);
    try testing.expectEqual(@as(f32, 3.0), t.scale.x);
    try testing.expectEqual(@as(f32, 4.0), t.scale.y);
    try testing.expectEqual(@as(f32, 5.0), t.depth);
}

test "a rotation authored as euler degrees reaches the component as a quaternion" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Turned"
        \\[entity.transform]
        \\rotation_euler = [0.0, 90.0, 0.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Turned");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const t = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, e) orelse return error.MissingComponent;
    try testing.expectApproxEqAbs(@as(f32, 0.0), t.rotation.x, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.70710678), t.rotation.y, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.0), t.rotation.z, 1e-5);
    try testing.expectApproxEqAbs(@as(f32, 0.70710678), t.rotation.w, 1e-5);
}

test "a key only the domain callback knows is not reported as unknown" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Turned"
        \\[entity.transform]
        \\rotation_euler = [0.0, 90.0, 0.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
}

test "a value only the domain callback can judge fails the load when it rejects it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Turned"
        \\[entity.transform]
        \\rotation_euler = "ninety"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "every sprite2d field the table describes reaches the component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Coin"
        \\[entity.sprite2d]
        \\texture    = "res://atlas.png"
        \\region     = [0.25, 0.5, 0.25, 0.5]
        \\size       = [2.0, 3.0]
        \\pivot      = [0.0, 1.0]
        \\flip_h     = true
        \\color      = [0.5, 0.6, 0.7, 0.8]
        \\alpha_mode = 2
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Coin");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const sp = f.comp(rc.ke_sprite2d_component, rc.KE_COMPONENT_NAME_SPRITE_2D, e) orelse return error.MissingComponent;
    try testing.expectEqualStrings("res://atlas.png", std.mem.sliceTo(&sp.texture, 0));
    try testing.expectEqual(@as(f32, 0.25), sp.region.x);
    try testing.expectEqual(@as(f32, 0.5), sp.region.w);
    try testing.expectEqual(@as(f32, 2.0), sp.size.x);
    try testing.expectEqual(@as(f32, 1.0), sp.pivot.y);
    try testing.expect(sp.flip_h != 0);
    try testing.expect(sp.flip_v == 0);
    try testing.expectEqual(@as(f32, 0.8), sp.color.w);
    try testing.expectEqual(@as(u32, rc.KE_ALPHA_MODE_BLEND), sp.alpha_mode);
    try testing.expect(sp.attached == 0);
}

test "a partial block leaves the header declared default standing" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Partial"
        \\[entity.mesh]
        \\color = [1.0, 0.0, 0.0, 1.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Partial");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const m = f.comp(rc.ke_mesh_component, rc.KE_COMPONENT_NAME_MESH, e) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, 1.0), m.base_color.x);
    try testing.expectEqual(@as(f32, 1.0), m.roughness);
    try testing.expectEqual(@as(f32, 1.5), m.ior);
    try testing.expectEqual(@as(f32, 0.5), m.alpha_cutoff);
}

test "a mesh is chosen by the name of its shape" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Crate"
        \\[entity.mesh]
        \\mesh = "cube"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Crate");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const m = f.comp(rc.ke_mesh_component, rc.KE_COMPONENT_NAME_MESH, e) orelse return error.MissingComponent;
    try testing.expectEqualStrings("cube", std.mem.sliceTo(&m.primitive, 0));
}

test "a camera keeps the planes it was authored with and the field table default for the rest" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Cam"
        \\[entity.camera]
        \\near_plane = 0.1
        \\far_plane = 100.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Cam");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const cam = f.comp(rc.ke_camera_component, rc.KE_COMPONENT_NAME_CAMERA, e) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, 0.1), cam.near_plane);
    try testing.expectEqual(@as(f32, 100.0), cam.far_plane);
    try testing.expectEqual(@as(f32, 60.0), cam.fov);
    try testing.expectEqual(@as(f32, 5.0), cam.orthographic_size);
}

test "every directional light field the table describes reaches the component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "SunVec"
        \\[entity.directional_light]
        \\direction = [-0.4, -1.0, -0.3]
        \\color = [1.0, 0.9, 0.8]
        \\ambient = [0.03, 0.03, 0.04]
        \\intensity = 3.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("SunVec");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const l = f.comp(rc.ke_directional_light_component, rc.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, e) orelse return error.MissingComponent;
    try testing.expectApproxEqAbs(@as(f32, -0.4), l.direction.x, 1e-6);
    try testing.expectEqual(@as(f32, -1.0), l.direction.y);
    try testing.expectApproxEqAbs(@as(f32, -0.3), l.direction.z, 1e-6);
    try testing.expectEqual(@as(f32, 1.0), l.color.x);
    try testing.expectApproxEqAbs(@as(f32, 0.9), l.color.y, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.8), l.color.z, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.03), l.ambient.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.04), l.ambient.z, 1e-6);
    try testing.expectEqual(@as(f32, 3.0), l.intensity);
}

test "every point light field the table describes reaches the component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Bulb"
        \\[entity.point_light]
        \\color = [0.2, 0.4, 0.6]
        \\radius = 12.5
        \\intensity = 2.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Bulb");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const l = f.comp(rc.ke_point_light_component, rc.KE_COMPONENT_NAME_POINT_LIGHT, e) orelse return error.MissingComponent;
    try testing.expectApproxEqAbs(@as(f32, 0.2), l.color.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.4), l.color.y, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), l.color.z, 1e-6);
    try testing.expectEqual(@as(f32, 12.5), l.radius);
    try testing.expectEqual(@as(f32, 2.0), l.intensity);
}

test "every spot light field the table describes reaches the component" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Lamp"
        \\[entity.spot_light]
        \\direction = [0.0, -1.0, 0.0]
        \\color = [1.0, 0.5, 0.25]
        \\inner_angle = 0.3
        \\outer_angle = 0.6
        \\range = 20.0
        \\intensity = 4.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Lamp");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const l = f.comp(rc.ke_spot_light_component, rc.KE_COMPONENT_NAME_SPOT_LIGHT, e) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, -1.0), l.direction.y);
    try testing.expectEqual(@as(f32, 1.0), l.color.x);
    try testing.expectEqual(@as(f32, 0.5), l.color.y);
    try testing.expectEqual(@as(f32, 0.25), l.color.z);
    try testing.expectApproxEqAbs(@as(f32, 0.3), l.inner_angle, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.6), l.outer_angle, 1e-6);
    try testing.expectEqual(@as(f32, 20.0), l.range);
    try testing.expectEqual(@as(f32, 4.0), l.intensity);
}

test "a label names its font by path" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Title"
        \\[entity.label]
        \\text      = "Pong"
        \\font      = "res://fonts/title.ttf"
        \\font_size = 72.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Title");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const l = f.comp(rc.ke_label_component, rc.KE_COMPONENT_NAME_LABEL, e) orelse return error.MissingComponent;
    try testing.expectEqualStrings("res://fonts/title.ttf", std.mem.sliceTo(&l.font, 0));
    try testing.expectEqual(@as(f32, 72.0), l.font_size);
    try testing.expectEqual(@as(u32, 0), l.font_handle.bits);
}

test "every label field the table describes reaches the component and its output stays empty" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Score"
        \\[entity.label]
        \\text = "0"
        \\anchor = [0.3, 0.0]
        \\offset = [0.0, 60.0]
        \\color = [0.95, 0.95, 0.95, 1.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Score");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const l = f.comp(rc.ke_label_component, rc.KE_COMPONENT_NAME_LABEL, e) orelse return error.MissingComponent;
    try testing.expectEqualStrings("0", std.mem.sliceTo(&l.text, 0));
    try testing.expectApproxEqAbs(@as(f32, 0.3), l.anchor[0], 1e-6);
    try testing.expectEqual(@as(f32, 60.0), l.offset[1]);
    try testing.expectEqual(@as(f32, 1.0), l.color[3]);
    try testing.expectEqual(@as(u32, 0), l.glyph_count);
}

test "a referenced scene is spliced under the name that referenced it" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("sub.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\
        \\[[entity]]
        \\name   = "Visual"
        \\parent = "Root"
        \\[entity.transform]
        \\scale = [0.3, 1.8, 1.0]
        \\
    );
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Holder"
        \\
        \\[[entity]]
        \\name  = "PaddleLeft"
        \\scene = "sub.scene.toml"
        \\[entity.transform]
        \\position = [-7.5, 0.0, 0.0]
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const paddle = f.find("PaddleLeft");
    try testing.expect(paddle != c.KE_ENTITY_INVALID);
    const visual = f.find("Visual");
    try testing.expect(visual != c.KE_ENTITY_INVALID);

    const vh = f.comp(c.ke_hierarchy_component, c.KE_COMPONENT_NAME_HIERARCHY, visual) orelse return error.MissingComponent;
    try testing.expectEqual(paddle, vh.parent);

    const pt = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, paddle) orelse return error.MissingComponent;
    try testing.expectEqual(@as(f32, -7.5), pt.position.x);

    const vt = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, visual) orelse return error.MissingComponent;
    try testing.expectApproxEqAbs(@as(f32, 0.3), vt.scale.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.8), vt.scale.y, 1e-6);
}

test "two instances of one subscene keep their own outer transform and overrides" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("sub.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\
    );
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Holder"
        \\
        \\[[entity]]
        \\name = "Left"
        \\scene = "sub.scene.toml"
        \\[entity.transform]
        \\position = [-7.5, 0.0, 0.0]
        \\[entity.camera]
        \\far_plane = 111.0
        \\
        \\[[entity]]
        \\name = "Right"
        \\scene = "sub.scene.toml"
        \\[entity.transform]
        \\position = [7.5, 0.0, 0.0]
        \\[entity.camera]
        \\far_plane = 222.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const left = f.find("Left");
    const right = f.find("Right");
    try testing.expect(left != c.KE_ENTITY_INVALID);
    try testing.expect(right != c.KE_ENTITY_INVALID);

    const lt = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, left) orelse return error.MissingComponent;
    const lc = f.comp(rc.ke_camera_component, rc.KE_COMPONENT_NAME_CAMERA, left) orelse return error.MissingComponent;
    const rt = f.comp(c.ke_transform_component, c.KE_COMPONENT_NAME_TRANSFORM, right) orelse return error.MissingComponent;
    const rcam = f.comp(rc.ke_camera_component, rc.KE_COMPONENT_NAME_CAMERA, right) orelse return error.MissingComponent;

    try testing.expectEqual(@as(f32, -7.5), lt.position.x);
    try testing.expectEqual(@as(f32, 111.0), lc.far_plane);
    try testing.expectEqual(@as(f32, 7.5), rt.position.x);
    try testing.expectEqual(@as(f32, 222.0), rcam.far_plane);
}

test "a component nobody registered fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Typo"
        \\[entity.point_ligth]
        \\radius = 42.0
        \\
    );

    var err: [*c]c.ke_error = null;
    try testing.expect(!f.loadReporting(try scene.cPath("main.scene.toml"), &err));
    try testing.expect(err != null);
}

test "a field a known component does not have fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Typo"
        \\[entity.point_light]
        \\radius = 4.0
        \\raidus = 9.0
        \\
    );

    var err: [*c]c.ke_error = null;
    try testing.expect(!f.loadReporting(try scene.cPath("main.scene.toml"), &err));
    try testing.expect(err != null);
}

test "a component the scene tree owns cannot be authored" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Parent"
        \\
        \\[[entity]]
        \\name   = "Child"
        \\parent = "Parent"
        \\[entity.hierarchy]
        \\parent = 999
        \\
    );

    var err: [*c]c.ke_error = null;
    try testing.expect(!f.loadReporting(try scene.cPath("main.scene.toml"), &err));
    try testing.expect(err != null);
}

test "the retired components nesting is refused rather than read" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Old"
        \\[entity.components.point_light]
        \\radius = 42.0
        \\
    );

    var err: [*c]c.ke_error = null;
    try testing.expect(!f.loadReporting(try scene.cPath("main.scene.toml"), &err));
    try testing.expect(err != null);
}

test "the script factory receives the entity and the normalized type name" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var spy: ScriptSpy = .{};
    const l = f.loader();
    try testing.expect(l.register_script_factory.?(l, spyFactory, &spy, null));

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Paddle"
        \\type = "PaddleController"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    try testing.expectEqual(@as(i32, 1), spy.calls);
    try testing.expectEqualStrings("paddle_controller", std.mem.sliceTo(&spy.last_type, 0));
    try testing.expectEqual(f.find("Paddle"), spy.last_entity);
}

fn normalizedName(name: [*c]const u8) []const u8 {
    const buf = struct {
        var storage: [type_name_max]u8 = undefined;
    };
    const out = normalizeTypeName(name, &buf.storage) orelse return "";
    return std.mem.sliceTo(out, 0);
}

test "a type name is spelled the same way whichever casing a scene authored" {
    try testing.expectEqualStrings("pong.ball", normalizedName("Pong.Ball"));
    try testing.expectEqualStrings("pong.ball", normalizedName("Pong+Ball"));
    try testing.expectEqualStrings("pong.ball", normalizedName("pong.ball"));
}

test "a run of capitals stays one word until a lowercase starts the next" {
    try testing.expectEqualStrings("http_server", normalizedName("HTTPServer"));
    try testing.expectEqualStrings("ui_label", normalizedName("UILabel"));
    try testing.expectEqualStrings("id", normalizedName("ID"));
}

test "a digit does not split the word it belongs to" {
    try testing.expectEqualStrings("sprite2d", normalizedName("Sprite2D"));
    try testing.expectEqualStrings("node3d", normalizedName("Node3D"));
    try testing.expectEqualStrings("collider2d", normalizedName("Collider2D"));
}

test "normalizing is idempotent, so a binding may apply it twice" {
    try testing.expectEqualStrings("paddle_controller", normalizedName("paddle_controller"));
    try testing.expectEqualStrings("pong.ball", normalizedName("pong.ball"));
    try testing.expectEqualStrings("sprite2d", normalizedName("sprite2d"));
}

test "a type name too long to normalize is refused rather than truncated" {
    var long: [type_name_max + 8]u8 = undefined;
    @memset(&long, 'A');
    long[long.len - 1] = 0;

    var buf: [type_name_max]u8 = undefined;
    try testing.expect(normalizeTypeName(@ptrCast(&long), &buf) == null);
}

test "a scene authoring a dotted type reaches the factory in snake case" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var spy: ScriptSpy = .{};
    const l = f.loader();
    try testing.expect(l.register_script_factory.?(l, spyFactory, &spy, null));

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Ball"
        \\type = "Pong.BallController"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    try testing.expectEqualStrings("pong.ball_controller", std.mem.sliceTo(&spy.last_type, 0));
}

test "an entity naming a type is still created when no script factory is registered" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Lone"
        \\type = "Whatever"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    try testing.expect(f.find("Lone") != c.KE_ENTITY_INVALID);
}

test "a user component is applied through the callback its owner registered" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    const e = &f.ecs.vtable;
    const demo_cid = e.component_register.?(e, "demo", @sizeOf(DemoComponent), null);
    try testing.expect(demo_cid != 0);
    const w = f.world_h.ref.?;
    try testing.expect(w.*.register_component_apply.?(w, demo_cid, demoApply, null));

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Test"
        \\[entity.demo]
        \\fov = 1.5
        \\mode = 7
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const entity = f.find("Test");
    try testing.expect(entity != c.KE_ENTITY_INVALID);

    const d: *DemoComponent = @ptrCast(@alignCast(fakeComponentGet(e, entity, demo_cid).?));
    try testing.expectEqual(@as(f32, 1.5), d.fov);
    try testing.expectEqual(@as(i32, 7), d.mode);
}

test "a loader is never created without a world" {
    try testing.expect(ke_scene_loader_create(null, null, null).ref == null);
}

test "destroying a null loader is safe" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    f.loader_h.destroy.?(null);
}

test "an audio player keeps the path and volume the scene authored" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Hit"
        \\[entity.audio_player]
        \\path = "assets/sounds/hit.wav"
        \\volume = 0.5
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Hit");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const a = f.comp(rc.ke_audio_player_component, rc.KE_COMPONENT_NAME_AUDIO_PLAYER, e) orelse return error.MissingComponent;
    try testing.expectEqualStrings("assets/sounds/hit.wav", std.mem.sliceTo(&a.path, 0));
    try testing.expectApproxEqAbs(@as(f32, 0.5), a.volume, 1e-6);
}

test "a collider keeps the extents and surface the scene authored" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Shape"
        \\[entity.collider2d]
        \\half_extents = [0.18, 0.18]
        \\restitution = 1.0
        \\friction = 0.0
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
    const e = f.find("Shape");
    try testing.expect(e != c.KE_ENTITY_INVALID);

    const col = f.comp(rc.ke_collider2d_component, rc.KE_COMPONENT_NAME_COLLIDER_2D, e) orelse return error.MissingComponent;
    try testing.expectApproxEqAbs(@as(f32, 0.18), col.half_extents.x, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.18), col.half_extents.y, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 1.0), col.restitution, 1e-6);
    try testing.expectApproxEqAbs(@as(f32, 0.0), col.friction, 1e-6);
}

test "a connection between two entities in the same scene reaches the bus" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "GoalScored"
        \\target = "Listener"
        \\handler = 7
        \\
        \\[[entity]]
        \\name = "Listener"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const emitter = f.find("Emitter");
    const listener = f.find("Listener");
    try testing.expect(emitter != c.KE_ENTITY_INVALID);
    try testing.expect(listener != c.KE_ENTITY_INVALID);

    const sig = try f.declaredSignal("GoalScored");
    try f.emitFrom(emitter, sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(listener, list[0].target);
    try testing.expectEqual(emitter, list[0].source);
    try testing.expectEqual(@as(u32, 7), list[0].handler_id);
}

test "a connect block that names no handler wires handler zero" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Listener"
        \\
        \\[[entity]]
        \\name = "Listener"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(f.find("Emitter"), sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(@as(u32, 0), list[0].handler_id);
}

test "a connection naming an entity the scene never declared fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Nobody"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "a connect block missing its signal fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\target = "Emitter"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "a connect block missing its target fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "a connection naming a signal nobody declared loads and registers that signal" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "NeverDeclaredAnywhere"
        \\target = "Emitter"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const sig = try f.declaredSignal("NeverDeclaredAnywhere");
    try f.emitFrom(f.find("Emitter"), sig);
    try testing.expectEqual(@as(usize, 1), f.delivered().len);
}

test "the same connection declared twice delivers once" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Listener"
        \\handler = 3
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Listener"
        \\handler = 3
        \\
        \\[[entity]]
        \\name = "Listener"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(f.find("Emitter"), sig);
    try testing.expectEqual(@as(usize, 1), f.delivered().len);
}

test "two connections of one signal that differ only by handler both deliver" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Listener"
        \\handler = 1
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Listener"
        \\handler = 2
        \\
        \\[[entity]]
        \\name = "Listener"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(f.find("Emitter"), sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expectEqual(@as(u32, 1), list[0].handler_id);
    try testing.expectEqual(@as(u32, 2), list[1].handler_id);
}

test "a connection resolves a target declared later in the same file" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "First"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Last"
        \\
        \\[[entity]]
        \\name = "Middle"
        \\
        \\[[entity]]
        \\name = "Last"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(f.find("First"), sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(f.find("Last"), list[0].target);
}

test "an entity may connect a signal to itself" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Loop"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Loop"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const loop = f.find("Loop");
    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(loop, sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(loop, list[0].target);
}

test "a connection declared inside a subscene wires that instance's own entities" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("sub.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\
        \\[[entity]]
        \\name = "Child"
        \\parent = "Root"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Root"
        \\
    );
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Holder"
        \\
        \\[[entity]]
        \\name = "Left"
        \\scene = "sub.scene.toml"
        \\
        \\[[entity]]
        \\name = "Right"
        \\scene = "sub.scene.toml"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const left_child = f.find("Left/Child");
    try testing.expect(left_child != c.KE_ENTITY_INVALID);

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(left_child, sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(f.find("Left"), list[0].target);
}

test "a connection in the outer scene cannot name an entity inside a spliced subscene" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("sub.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\
        \\[[entity]]
        \\name = "Child"
        \\parent = "Root"
        \\
    );
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Holder"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Child"
        \\
        \\[[entity]]
        \\name = "Left"
        \\scene = "sub.scene.toml"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "an entity that splices a subscene connects from the subscene's root" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("sub.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\
    );
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Holder"
        \\
        \\[[entity]]
        \\name = "Left"
        \\scene = "sub.scene.toml"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Holder"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));

    const left = f.find("Left");
    try testing.expect(left != c.KE_ENTITY_INVALID);

    const sig = try f.declaredSignal("Poke");
    try f.emitFrom(left, sig);

    const list = f.delivered();
    try testing.expectEqual(@as(usize, 1), list.len);
    try testing.expectEqual(f.find("Holder"), list[0].target);
}

test "a scene that declares a connection fails when the world has no signal bus" {
    var f: Fixture = undefined;
    try f.initEx(false);
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[[entity.connect]]
        \\signal = "Poke"
        \\target = "Emitter"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}

test "a scene without connections loads on a world that has no signal bus" {
    var f: Fixture = undefined;
    try f.initEx(false);
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\
    );

    try testing.expect(f.load(try scene.cPath("main.scene.toml")));
}

test "a connect written as a single table instead of an array fails the load" {
    var f: Fixture = undefined;
    try f.init();
    defer f.deinit();

    var scene = TempScene.init();
    defer scene.deinit();
    try scene.put("main.scene.toml",
        \\[[entity]]
        \\name = "Emitter"
        \\[entity.connect]
        \\signal = "Poke"
        \\target = "Nobody"
        \\
    );

    try testing.expect(!f.load(try scene.cPath("main.scene.toml")));
}
