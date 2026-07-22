// ke_scene_loader impl, tomlc99 backed.
//
// Walks a `.scene.toml` file:
//   [[entity]] entries -> tree.create_node + transform/components apply +
//   script factory dispatch + properties bag.
//
// [entity.components.X] uses the world's apply registry: look the cid up by
// name, add the component, build a variant-table entry list from the TOML
// table, call the registered apply_fn. Components without a registered apply
// are silently skipped.
//
// scene_properties lifetime: every per-entity allocation (strings + entries)
// comes from the loader's arena and is freed at loader destroy. The arena is
// conceptually owned by the world (it outlives the entity); parking it in the
// loader gives the same end behavior with a simpler ownership graph.

const std = @import("std");

const c = @import("c.zig").c;
const heap = @import("heap.zig");

const E = @import("kerror").Errors(c);

/// Longest project root / scene directory path the loader tracks.
const path_max = 512;
/// Longest resolved scene path handed to fopen.
const resolved_path_max = 1024;

const res_prefix = "res://";

// -- arena -------------------------------------------------------------------
//
// Backs scene_properties components and the variant entries they point at.
// Nothing here is ever freed individually — the whole arena goes at once when
// the loader is destroyed — so std.heap.ArenaAllocator over the plugin heap is
// the exact shape this needs, with none of a chunk allocator's bookkeeping
// hand-rolled again.

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

    scene_properties_cid: c.ke_component_id,

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

// -- variant construction ----------------------------------------------------

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

// -- TOML -> variant ---------------------------------------------------------

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

// -- path resolution ---------------------------------------------------------

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

// -- script dispatch ---------------------------------------------------------

fn dispatchScript(s: *State, entity: c.ke_entity, type_name: [*c]const u8) void {
    // The factory reports its own success; a script that fails to bind must not
    // abort the rest of the scene load.
    if (s.script_factory) |factory| _ = factory(s.script_ctx, entity, type_name, null);
}

// -- properties bag ----------------------------------------------------------

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

fn attachProperties(s: *State, entity: c.ke_entity, props_tbl: *c.toml_table_t) void {
    const world = s.world;
    const e = ecsOf(world) orelse return;

    const entries = buildEntries(s, props_tbl) orelse return;

    const comp = e.component_add.?(e, entity, s.scene_properties_cid) orelse return;
    const bag: *c.ke_scene_properties = @ptrCast(@alignCast(comp));
    bag.entries = entries.ptr;
    bag.count = @intCast(entries.len);
}

// -- components application via apply registry -------------------------------

fn applyComponentBlock(
    s: *State,
    entity: c.ke_entity,
    comp_name: [*c]const u8,
    comp_tbl: *c.toml_table_t,
) void {
    const world = s.world;
    const e = ecsOf(world) orelse return;

    var meta: c.ke_component_meta = undefined;
    if (!e.component_lookup.?(e, comp_name, &meta, null)) return; // unknown component; skip

    const comp = e.component_add.?(e, entity, meta.cid) orelse return;

    // No apply registered means no field mapping is defined for this component.
    const apply_fn = world.get_component_apply.?(world, meta.cid) orelse return;

    // Entries come from the arena rather than a fixed stack buffer, so a
    // component block with many fields is applied whole instead of truncated.
    const entries = buildEntries(s, comp_tbl) orelse return;
    apply_fn(comp, entries.ptr, @intCast(entries.len));
}

/// [entity.transform] is sugar for [entity.components.transform].
fn applyTransformBlock(s: *State, entity: c.ke_entity, xform_tbl: *c.toml_table_t) void {
    applyComponentBlock(s, entity, c.KE_COMPONENT_NAME_TRANSFORM, xform_tbl);
}

/// A subscene's outer [[entity]] block may carry a [transform] override. It is
/// applied BEFORE dispatch_script so OnBind sees the final position/rotation/
/// scale; the remaining outer overrides are applied afterwards.
fn applyOuterTransformEarly(s: *State, entity: c.ke_entity, outer: ?*c.toml_table_t) void {
    const o = outer orelse return;
    if (c.toml_table_in(o, "transform")) |xt| applyTransformBlock(s, entity, xt);
}

fn applyComponentsSection(s: *State, entity: c.ke_entity, comps: *c.toml_table_t) void {
    var i: c_int = 0;
    while (true) : (i += 1) {
        const cn = c.toml_key_in(comps, i) orelse break;
        if (c.toml_table_in(comps, cn)) |ct| applyComponentBlock(s, entity, cn, ct);
    }
}

fn applyOuterOverrides(s: *State, entity: c.ke_entity, outer: *c.toml_table_t) void {
    // [entity.transform] was already applied by applyOuterTransformEarly; doing
    // it again here would be a redundant write.
    if (c.toml_table_in(outer, "properties")) |props| attachProperties(s, entity, props);
    const type_d = c.toml_string_in(outer, "type");
    if (type_d.ok != 0) {
        dispatchScript(s, entity, type_d.u.s);
        std.c.free(type_d.u.s);
    }
    if (c.toml_table_in(outer, "components")) |comps| applyComponentsSection(s, entity, comps);
}

// -- entity processing -------------------------------------------------------

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
        // The name lives in the arena: the TOML datum it came from is freed by
        // the caller as soon as the entity is processed.
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

    // A `scene = "..."` reference splices another scene file in under `parent`.
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

    if (c.toml_table_in(args.entity_tbl, "transform")) |xt| applyTransformBlock(s, entity, xt);

    // The outer override must land before dispatch_script so OnBind sees it.
    applyOuterTransformEarly(s, entity, args.override_outer);

    const type_d = c.toml_string_in(args.entity_tbl, "type");
    if (type_d.ok != 0) {
        dispatchScript(s, entity, type_d.u.s);
        std.c.free(type_d.u.s);
    }

    if (c.toml_table_in(args.entity_tbl, "properties")) |props| attachProperties(s, entity, props);
    if (c.toml_table_in(args.entity_tbl, "components")) |comps| applyComponentsSection(s, entity, comps);
    if (args.override_outer) |outer| applyOuterOverrides(s, entity, outer);

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
    const root = c.toml_parse_file(@ptrCast(fp), &errbuf, errbuf.len);
    _ = std.c.fclose(fp);
    if (root == null) {
        E.fail(out_error, .io, "failed to parse scene file", @src());
        return false;
    }
    defer c.toml_free(root);

    var base_buf: [path_max]u8 = undefined;
    const base_dir = pathDirname(std.mem.span(path), &base_buf);

    // A scene with no [[entity]] array is valid and simply contributes nothing.
    const entities = c.toml_array_in(root, "entity") orelse {
        if (out_root) |r| r.* = c.KE_ENTITY_INVALID;
        return true;
    };

    var names: NameMap = .{ .arena = &s.arena };
    defer names.deinit();

    var first_root: c.ke_entity = c.KE_ENTITY_INVALID;
    const n = c.toml_array_nelem(entities);
    var is_first = true;
    var i: c_int = 0;
    while (i < n) : (i += 1) {
        const et = c.toml_table_at(entities, i) orelse continue;
        var ent: c.ke_entity = c.KE_ENTITY_INVALID;

        // Only the first entity inherits the caller's attach point and name
        // override — it is the subscene's root.
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
        if (is_first) {
            first_root = ent;
            is_first = false;
        }
    }

    if (out_root) |r| r.* = first_root;
    return true;
}

// -- vtable ------------------------------------------------------------------

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

// -- factory -----------------------------------------------------------------

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
        .scene_properties_cid = 0,
        .arena = .init(),
    };

    if (project_root != null) {
        const root = std.mem.span(project_root);
        const n = @min(root.len, s.project_root.len - 1);
        @memcpy(s.project_root[0..n], root[0..n]);
        s.project_root[n] = 0;
    }

    // scene_properties has no apply callback: its layout (entries pointer +
    // count) is populated wholesale by attachProperties, not field by field.
    const e = ecsOf(world) orelse {
        heap.gpa.destroy(s);
        E.fail(out_error, .not_initialized, "world has no ecs", @src());
        return null_handle;
    };
    var meta: c.ke_component_meta = undefined;
    s.scene_properties_cid = if (e.component_lookup.?(e, c.KE_SCENE_PROPERTIES_COMPONENT_NAME, &meta, null))
        meta.cid
    else
        e.component_register.?(e, c.KE_SCENE_PROPERTIES_COMPONENT_NAME, @sizeOf(c.ke_scene_properties));

    s.api.handle = s;
    s.api.load = vtLoad;
    s.api.register_script_factory = vtRegisterScriptFactory;

    return .{ .ref = &s.api, .destroy = vtDestroy };
}
