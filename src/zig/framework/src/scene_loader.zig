
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

fn dispatchScript(s: *State, entity: c.ke_entity, type_name: [*c]const u8) void {
    if (s.script_factory) |factory| _ = factory(s.script_ctx, entity, type_name, null);
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
    if (apply_fn) |f| f(comp, entries.ptr, @intCast(entries.len));

    for (entries) |*entry| {
        if (entry.consumed) continue;
        structural(world, out_error, "component '{s}' has no field '{s}'", .{ comp_name, entry.key });
        return false;
    }
    return true;
}

/// Whether a table under `[[entity]]` describes something other than a component.
fn reservedBlock(key: [*c]const u8) bool {
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
        if (reservedBlock(key)) continue;
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
