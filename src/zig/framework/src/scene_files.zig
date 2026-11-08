//! Scene files: reads a scene file and records, into the commands it is given, a node of the
//! declared type for each entry, with the values its blocks write over the components' defaults.

const std = @import("std");

const c = @import("c");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_ecs = @import("abi_ecs");
const abi_ecs_variant = @import("abi_ecs_variant");
const abi_framework = @import("abi_framework");
const abi_io = @import("abi_io");
const abi_result = @import("abi_result");
const heap = @import("heap");
const file_read = @import("file_read.zig");
const fields_apply = @import("component_fields_apply.zig");
const values = @import("scene_values.zig");
const names_mod = @import("scene_names.zig");
const Arena = values.Arena;
const NameMap = names_mod.NameMap;

const R = @import("result").Result(.{});
const log = std.log.scoped(.framework);

const Entity = abi_ecs.c.ke_entity;
const Cid = abi_ecs.c.ke_component_id;
const invalid = abi_ecs.c.KE_ENTITY_INVALID;
const res_prefix = "res://";
const base_type = "node";
const type_tag_prefix = "node.";
const format_version: i64 = 2;
const component_alignment: std.mem.Alignment = .@"16";

/// Created by `ke_scene_files_create` and freed by `vtDestroy`. It holds only borrowed services;
/// what one instantiate reads lives in an arena of that call.
const State = struct {
    api: abi_framework.c.ke_scene_files,
    ecs: *abi_ecs.c.ke_ecs,
    types: *abi_framework.c.ke_node_types,
    assets: *abi_asset_resolver.c.ke_asset_resolver,
    io: *abi_io.c.ke_io,
};

fn stateOf(self: ?*abi_framework.c.ke_scene_files) ?*State {
    const api = self orelse return null;
    return @ptrCast(@alignCast(api.handle orelse return null));
}

/// The bytes one component of the node being read will be attached with: its defaults, then
/// every block written for it, in the order they are read.
const Pending = struct {
    cid: Cid,
    bytes: []align(16) u8,
};

/// What one instantiate works with: the queue it records into and the arena its reads live in.
const Load = struct {
    s: *State,
    commands: *abi_ecs.c.ke_ecs_commands,
    arena: Arena,
};

fn structural(comptime fmt: []const u8, args: anytype) R.Error {
    log.warn(fmt, args);
    return error.InvalidArgument;
}

fn pathDirname(path: []const u8) []const u8 {
    const idx = std.mem.lastIndexOfAny(u8, path, "/\\") orelse return ".";
    return path[0..idx];
}

fn resolvePath(s: *const State, base_dir: []const u8, ref: [*:0]const u8, out: []u8) R.Error!void {
    const r = std.mem.span(ref);
    if (std.mem.startsWith(u8, r, res_prefix)) {
        R.check(s.assets.resolve_path.?(s.assets, ref, out.ptr, out.len)) catch |err| {
            log.warn("scene files: the asset resolver could not resolve '{s}'", .{r});
            return err;
        };
        return;
    }
    const absolute = r.len > 0 and (r[0] == '/' or (r.len > 1 and r[1] == ':'));
    const written = if (absolute) std.fmt.bufPrintZ(out, "{s}", .{r}) else std.fmt.bufPrintZ(out, "{s}/{s}", .{ base_dir, r });
    _ = written catch return structural("scene files: the path '{s}' does not fit", .{r});
}

fn checkHeader(root: *c.toml_table_t) R.Error!void {
    var i: c_int = 0;
    while (c.toml_key_in(root, i)) |key| : (i += 1) {
        const k = std.mem.span(key);
        if (std.mem.eql(u8, k, "entity") or std.mem.eql(u8, k, "scene")) continue;
        return structural("scene files: top-level key '{s}' is not entity or scene", .{k});
    }
    const header = c.toml_table_in(root, "scene") orelse return;
    var j: c_int = 0;
    while (c.toml_key_in(header, j)) |key| : (j += 1) {
        if (std.mem.eql(u8, std.mem.span(key), "version")) continue;
        return structural("scene files: [scene] key '{s}' is not version", .{key});
    }
    const version = c.toml_int_in(header, "version");
    if (version.ok != 0 and version.u.i != format_version) {
        return structural("scene files: format version {d} is not {d}", .{ version.u.i, format_version });
    }
}

fn entryKey(key: []const u8) bool {
    for ([_][]const u8{ "name", "parent", "scene", "type" }) |known| {
        if (std.mem.eql(u8, key, known)) return true;
    }
    return false;
}

fn lookup(s: *State, comptime fmt: []const u8, args: anytype) ?abi_ecs.c.ke_component_meta {
    const z = std.fmt.allocPrintSentinel(heap.gpa, fmt, args, 0) catch return null;
    defer heap.gpa.free(z);
    var meta = std.mem.zeroes(abi_ecs.c.ke_component_meta);
    if (!s.ecs.component_lookup.?(s.ecs, z.ptr, &meta)) return null;
    return meta;
}

fn resolveBlock(s: *State, tag: Cid, type_name: []const u8, block: []const u8) ?abi_ecs.c.ke_component_meta {
    if (lookup(s, "{s}", .{block})) |meta| {
        if (s.types.carries.?(s.types, tag, meta.cid)) return meta;
    }
    const dot = std.mem.lastIndexOfScalar(u8, type_name, '.') orelse return null;
    const meta = lookup(s, "{s}.{s}", .{ type_name[0..dot], block }) orelse return null;
    return if (s.types.carries.?(s.types, tag, meta.cid)) meta else null;
}

fn pendingFor(s: *State, pending: *std.ArrayList(Pending), meta: abi_ecs.c.ke_component_meta) R.Error!*Pending {
    for (pending.items) |*p| if (p.cid == meta.cid) return p;
    const bytes = heap.gpa.alignedAlloc(u8, component_alignment, meta.size) catch return error.OutOfMemory;
    @memset(bytes, 0);
    if (meta.fields) |f| fields_apply.seedDefaults(s.ecs, bytes.ptr, f, meta.field_count);
    pending.append(heap.gpa, .{ .cid = meta.cid, .bytes = bytes }) catch {
        heap.gpa.free(bytes);
        return error.OutOfMemory;
    };
    return &pending.items[pending.items.len - 1];
}

fn writeBlocks(load: *Load, tbl: *c.toml_table_t, tag: Cid, type_name: []const u8, pending: *std.ArrayList(Pending)) R.Error!void {
    const s = load.s;
    var i: c_int = 0;
    while (c.toml_key_in(tbl, i)) |key_z| : (i += 1) {
        const key = std.mem.span(key_z);
        if (std.mem.eql(u8, key, "connect")) {
            return structural("scene files: [[entity.connect]] is not read; a node raises an event instead", .{});
        }
        const block = c.toml_table_in(tbl, key_z) orelse {
            if (entryKey(key)) continue;
            return structural("scene files: entry key '{s}' is not name, parent, scene, type or a component block", .{key});
        };
        const meta = resolveBlock(s, tag, type_name, key) orelse
            return structural("scene files: a node of type '{s}' carries no component '{s}'", .{ type_name, key });
        const meta_fields = meta.fields orelse
            return structural("scene files: component '{s}' has no field table", .{key});
        const p = try pendingFor(s, pending, meta);
        const entries = values.buildEntries(&load.arena, block) orelse continue;
        if (fields_apply.apply(s.ecs, p.bytes.ptr, entries.ptr, @intCast(entries.len), meta_fields, meta.field_count)) |refusing| {
            return structural("scene files: field '{s}' of '{s}' cannot hold the value written for it", .{ refusing.name.?, key });
        }
        for (entries) |entry| {
            if (!entry.consumed) return structural("scene files: component '{s}' has no field '{s}'", .{ key, entry.key.? });
        }
    }
}

fn freePending(pending: *std.ArrayList(Pending)) void {
    for (pending.items) |p| heap.gpa.free(p.bytes);
    pending.deinit(heap.gpa);
}

/// The first entry of a file read for a referencing entry takes that entry's name and blocks;
/// every entry without a parent of its own goes under the parent.
const Outer = struct {
    name: ?[*:0]const u8 = null,
    parent: Entity = invalid,
    table: ?*c.toml_table_t = null,
};

fn processEntry(load: *Load, base_dir: []const u8, tbl: *c.toml_table_t, names: *NameMap, outer: Outer) R.Error!Entity {
    const s = load.s;
    const name_d = c.toml_string_in(tbl, "name");
    defer if (name_d.ok != 0) std.c.free(name_d.u.s);
    if (name_d.ok == 0 and outer.name == null) return structural("scene files: an entry has no name", .{});
    const name: [*:0]const u8 = outer.name orelse name_d.u.s;

    var parent = outer.parent;
    const parent_d = c.toml_string_in(tbl, "parent");
    if (parent_d.ok != 0) {
        defer std.c.free(parent_d.u.s);
        parent = switch (names.find(std.mem.span(parent_d.u.s))) {
            .one => |e| e,
            .none => return structural("scene files: parent '{s}' is not an entry declared before it", .{parent_d.u.s}),
            .ambiguous => return structural("scene files: parent '{s}' names more than one entry", .{parent_d.u.s}),
        };
    }

    const type_d = c.toml_string_in(tbl, "type");
    defer if (type_d.ok != 0) std.c.free(type_d.u.s);
    const scene_d = c.toml_string_in(tbl, "scene");
    if (scene_d.ok != 0) {
        defer std.c.free(scene_d.u.s);
        if (type_d.ok != 0) return structural("scene files: '{s}' names both a scene and a type; a node has one type", .{name});
        var path: [std.fs.max_path_bytes]u8 = undefined;
        try resolvePath(s, base_dir, scene_d.u.s, &path);
        const root = try loadFile(load, @ptrCast(&path), .{ .name = name, .parent = parent, .table = tbl });
        if (name_d.ok != 0) names.put(name_d.u.s, root) catch return error.OutOfMemory;
        return root;
    }

    const type_name: []const u8 = if (type_d.ok != 0) std.mem.span(type_d.u.s) else base_type;
    const tag = (lookup(s, "{s}{s}", .{ type_tag_prefix, type_name }) orelse {
        log.warn("scene files: type '{s}' was never registered", .{type_name});
        return error.NotFound;
    }).cid;

    var node: Entity = invalid;
    try R.check(s.types.spawn.?(s.types, load.commands, tag, name, parent, &node));

    var pending: std.ArrayList(Pending) = .empty;
    defer freePending(&pending);
    try writeBlocks(load, tbl, tag, type_name, &pending);
    if (outer.table) |t| try writeBlocks(load, t, tag, type_name, &pending);
    for (pending.items) |p| {
        try R.check(load.commands.attach.?(load.commands, node, p.cid, p.bytes.ptr, p.bytes.len));
    }

    if (name_d.ok != 0) names.put(name_d.u.s, node) catch return error.OutOfMemory;
    return node;
}

fn loadFile(load: *Load, path: [*:0]const u8, outer: Outer) R.Error!Entity {
    const text = file_read.readText(load.s.io, path) catch |err| {
        log.warn("scene files: reading {s} failed: {t}", .{ path, err });
        return err;
    };
    defer heap.gpa.free(text);
    var errbuf: [200]u8 = undefined;
    const root = c.toml_parse(text.ptr, &errbuf, errbuf.len) orelse {
        log.warn("scene files: {s} does not parse: {s}", .{ path, std.mem.sliceTo(&errbuf, 0) });
        return error.Io;
    };
    defer c.toml_free(root);
    try checkHeader(root);

    const entries = c.toml_array_in(root, "entity") orelse return invalid;
    var names: NameMap = .{ .arena = &load.arena };
    defer names.deinit();
    const base_dir = pathDirname(std.mem.span(path));
    var first: Entity = invalid;
    var i: c_int = 0;
    while (i < c.toml_array_nelem(entries)) : (i += 1) {
        const tbl = c.toml_table_at(entries, i) orelse continue;
        const node = try processEntry(load, base_dir, tbl, &names, if (i == 0) outer else .{ .parent = outer.parent });
        if (i == 0) first = node;
    }
    return first;
}

/// Slot `instantiate`.
fn instantiate(self: ?*abi_framework.c.ke_scene_files, path_in: ?[*:0]const u8, parent: Entity, commands_in: ?*abi_ecs.c.ke_ecs_commands, out_root: ?*Entity) callconv(.c) abi_result.c.ke_result {
    if (out_root) |r| r.* = invalid;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const path_ref = path_in orelse return R.code(error.InvalidArgument);
    const commands = commands_in orelse return R.code(error.InvalidArgument);
    var load: Load = .{ .s = s, .commands = commands, .arena = .init() };
    defer load.arena.deinit();
    var path: [std.fs.max_path_bytes]u8 = undefined;
    resolvePath(s, ".", path_ref, &path) catch |err| return R.code(err);
    const root = loadFile(&load, @ptrCast(&path), .{ .parent = parent }) catch |err| return R.code(err);
    if (out_root) |r| r.* = root;
    return R.ok;
}

fn vtDestroy(self: ?*abi_framework.c.ke_scene_files) callconv(.c) void {
    const s = stateOf(self) orelse return;
    heap.gpa.destroy(s);
}

/// Factory. A null ecs, node types, asset resolver, io or out handle fails as an invalid
/// argument and a failed allocation as out of memory; each leaves the handle zeroed.
export fn ke_scene_files_create(
    ecs_in: ?*abi_ecs.c.ke_ecs,
    types_in: ?*abi_framework.c.ke_node_types,
    assets_in: ?*abi_asset_resolver.c.ke_asset_resolver,
    io_in: ?*abi_io.c.ke_io,
    out_files: ?*abi_framework.c.ke_scene_files_handle,
) callconv(.c) abi_result.c.ke_result {
    const out = out_files orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_framework.c.ke_scene_files_handle);
    const ecs = ecs_in orelse return R.code(error.InvalidArgument);
    const types = types_in orelse return R.code(error.InvalidArgument);
    const assets = assets_in orelse return R.code(error.InvalidArgument);
    const io = io_in orelse return R.code(error.InvalidArgument);
    const s = heap.gpa.create(State) catch return R.code(error.OutOfMemory);
    s.* = .{ .api = .{ .instantiate = &instantiate }, .ecs = ecs, .types = types, .assets = assets, .io = io };
    s.api.handle = s;
    out.* = .{ .ref = &s.api, .destroy = vtDestroy };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");
const served_files = @import("served_files_test.zig");

const Paddle = extern struct { speed: f32, half: f32 };
const Pose = extern struct { x: f32, y: f32 };

const paddle_fields = [_]abi_ecs.c.ke_component_field{
    .{ .name = "speed", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(Paddle, "speed"), .size = 4, .default_value = .{ .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .unnamed_0 = .{ .f = 7 } } },
    .{ .name = "half", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(Paddle, "half"), .size = 4 },
};
const pose_fields = [_]abi_ecs.c.ke_component_field{
    .{ .name = "x", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(Pose, "x"), .size = 4 },
    .{ .name = "y", .type = abi_ecs_variant.c.KE_VARIANT_FLOAT, .offset = @offsetOf(Pose, "y"), .size = 4 },
};

const Known = struct { name: []const u8, meta: abi_ecs.c.ke_component_meta };
const components = [_]Known{
    .{ .name = "node.node", .meta = .{ .cid = 1 } },
    .{ .name = "node.pong.paddle", .meta = .{ .cid = 2 } },
    .{ .name = "pong.paddle", .meta = .{ .cid = 3, .size = @sizeOf(Paddle), .alignment = 4, .fields = &paddle_fields, .field_count = paddle_fields.len } },
    .{ .name = "pose", .meta = .{ .cid = 4, .size = @sizeOf(Pose), .alignment = 4, .fields = &pose_fields, .field_count = pose_fields.len } },
    .{ .name = "node.marker", .meta = .{ .cid = 5 } },
};

fn lookupKnown(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_lookup)) bool {
    const name = std.mem.span(args[1].?);
    for (components) |k| if (std.mem.eql(u8, k.name, name)) {
        args[2].?.* = k.meta;
        return true;
    };
    return false;
}

fn writeFloat(args: zsub.For(abi_ecs.c.ke_ecs).Args(.component_field_write)) abi_result.c.ke_result {
    const field = args[2].?;
    const v = args[3].?;
    if (v.type != abi_ecs_variant.c.KE_VARIANT_FLOAT) return R.code(error.InvalidArgument);
    const at: *align(1) f32 = @ptrCast(@as([*]u8, @ptrCast(args[1].?)) + field.offset);
    at.* = @floatCast(v.unnamed_0.f);
    return R.ok;
}

fn carriesKnown(args: zsub.For(abi_framework.c.ke_node_types).Args(.carries)) bool {
    return args[1] == 2 and (args[2] == 3 or args[2] == 4);
}

const Spawned = struct { tag: Cid, name: [32]u8, parent: Entity };
var spawned: [8]Spawned = undefined;
var spawned_count: usize = 0;

fn spawnNode(args: zsub.For(abi_framework.c.ke_node_types).Args(.spawn)) abi_result.c.ke_result {
    var row: Spawned = .{ .tag = args[2], .name = std.mem.zeroes([32]u8), .parent = args[4] };
    const name = std.mem.span(args[3].?);
    @memcpy(row.name[0..name.len], name);
    spawned[spawned_count] = row;
    spawned_count += 1;
    args[5].?.* = 100 + spawned_count;
    return R.ok;
}

const Attached = struct { node: Entity, cid: Cid, bytes: [8]u8 };
var attached: [8]Attached = undefined;
var attached_count: usize = 0;

fn recordAttach(args: zsub.For(abi_ecs.c.ke_ecs_commands).Args(.attach)) abi_result.c.ke_result {
    var row: Attached = .{ .node = args[1], .cid = args[2], .bytes = std.mem.zeroes([8]u8) };
    const data: [*]const u8 = @ptrCast(args[3].?);
    @memcpy(row.bytes[0..args[4]], data[0..args[4]]);
    attached[attached_count] = row;
    attached_count += 1;
    return R.ok;
}

fn resolveRes(args: zsub.For(abi_asset_resolver.c.ke_asset_resolver).Args(.resolve_path)) abi_result.c.ke_result {
    const ref = std.mem.span(args[1].?);
    _ = std.fmt.bufPrintZ(args[2].?[0..args[3]], "/scenes/{s}", .{ref[res_prefix.len..]}) catch return R.code(error.InvalidArgument);
    return R.ok;
}

const Fixture = struct {
    ecs: zsub.For(abi_ecs.c.ke_ecs) = undefined,
    types: zsub.For(abi_framework.c.ke_node_types) = undefined,
    assets: zsub.For(abi_asset_resolver.c.ke_asset_resolver) = undefined,
    commands: zsub.For(abi_ecs.c.ke_ecs_commands) = undefined,
    files: abi_framework.c.ke_scene_files_handle = undefined,

    fn init(f: *Fixture) !void {
        spawned_count = 0;
        attached_count = 0;
        try f.ecs.init();
        try f.types.init();
        try f.assets.init();
        try f.commands.init();
        _ = f.ecs.when(.component_lookup).does(lookupKnown);
        _ = f.ecs.when(.component_field_write).does(writeFloat);
        _ = f.types.when(.carries).does(carriesKnown);
        _ = f.types.when(.spawn).does(spawnNode);
        _ = f.assets.when(.resolve_path).does(resolveRes);
        _ = f.commands.when(.attach).does(recordAttach);
        try R.check(ke_scene_files_create(f.ecs.api(), f.types.api(), f.assets.api(), served_files.io(), &f.files));
    }

    fn deinit(f: *Fixture) void {
        f.files.destroy.?(f.files.ref);
        f.commands.deinit();
        f.assets.deinit();
        f.types.deinit();
        f.ecs.deinit();
    }

    fn instantiate(f: *Fixture, path: [*:0]const u8, parent: Entity) abi_result.c.ke_result {
        var root: Entity = invalid;
        return f.files.ref.?.instantiate.?(f.files.ref, path, parent, f.commands.api(), &root);
    }
};

fn floatAt(row: Attached, offset: usize) f32 {
    return std.mem.bytesToValue(f32, row.bytes[offset..][0..4]);
}

test "each entry spawns a node of its type, named, under the parent; an entry without a type is a base node" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try served_files.put("/scenes/two.scene.toml",
        \\[[entity]]
        \\name = "Paddle"
        \\type = "pong.paddle"
        \\[[entity]]
        \\name = "Group"
        \\parent = "Paddle"
    );
    defer served_files.remove("/scenes/two.scene.toml");
    try R.check(f.instantiate("/scenes/two.scene.toml", 9));
    try testing.expectEqual(@as(usize, 2), spawned_count);
    try testing.expectEqual(@as(Cid, 2), spawned[0].tag);
    try testing.expectEqualStrings("Paddle", std.mem.sliceTo(&spawned[0].name, 0));
    try testing.expectEqual(@as(Entity, 9), spawned[0].parent);
    try testing.expectEqual(@as(Cid, 1), spawned[1].tag);
    try testing.expectEqual(@as(Entity, 101), spawned[1].parent);
}

test "every entry without a parent of its own goes under the parent, not only the first" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try served_files.put("/scenes/flat.scene.toml",
        \\[[entity]]
        \\name = "Ambient"
        \\[[entity]]
        \\name = "Camera"
        \\[[entity]]
        \\name = "Controller"
    );
    defer served_files.remove("/scenes/flat.scene.toml");
    try R.check(f.instantiate("/scenes/flat.scene.toml", 9));
    try testing.expectEqual(@as(usize, 3), spawned_count);
    for (spawned[0..3]) |node| try testing.expectEqual(@as(Entity, 9), node.parent);
}

test "a block named in the type's namespace writes over the component's defaults, attached once" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try served_files.put("/scenes/paddle.scene.toml",
        \\[[entity]]
        \\name = "Paddle"
        \\type = "pong.paddle"
        \\[entity.paddle]
        \\half = 0.5
        \\[entity.pose]
        \\x = 2.0
    );
    defer served_files.remove("/scenes/paddle.scene.toml");
    try R.check(f.instantiate("/scenes/paddle.scene.toml", invalid));
    try testing.expectEqual(@as(usize, 2), attached_count);
    try testing.expectEqual(@as(Cid, 3), attached[0].cid);
    try testing.expectEqual(@as(f32, 7), floatAt(attached[0], 0));
    try testing.expectEqual(@as(f32, 0.5), floatAt(attached[0], 4));
    try testing.expectEqual(@as(f32, 2), floatAt(attached[1], 0));
}

test "a referenced scene's first node takes the referencing name, parent and blocks over its own" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try served_files.put("/scenes/paddle.scene.toml",
        \\[[entity]]
        \\name = "Root"
        \\type = "pong.paddle"
        \\[entity.paddle]
        \\speed = 3.0
        \\half = 0.5
    );
    defer served_files.remove("/scenes/paddle.scene.toml");
    try served_files.put("/scenes/main.scene.toml",
        \\[[entity]]
        \\name = "Left"
        \\scene = "res://paddle.scene.toml"
        \\[entity.paddle]
        \\half = 0.25
    );
    defer served_files.remove("/scenes/main.scene.toml");
    try R.check(f.instantiate("res://main.scene.toml", 4));
    try testing.expectEqual(@as(usize, 1), spawned_count);
    try testing.expectEqualStrings("Left", std.mem.sliceTo(&spawned[0].name, 0));
    try testing.expectEqual(@as(Entity, 4), spawned[0].parent);
    try testing.expectEqual(@as(usize, 1), attached_count);
    try testing.expectEqual(@as(f32, 3), floatAt(attached[0], 0));
    try testing.expectEqual(@as(f32, 0.25), floatAt(attached[0], 4));
}

fn expectRefused(code: R.Error, text: []const u8) !void {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try served_files.put("/scenes/bad.scene.toml", text);
    defer served_files.remove("/scenes/bad.scene.toml");
    try testing.expectEqual(R.code(code), f.instantiate("/scenes/bad.scene.toml", invalid));
}

test "a block the type does not carry, a field it lacks or a value it cannot hold is refused" {
    try expectRefused(error.InvalidArgument, "[[entity]]\nname = \"M\"\ntype = \"marker\"\n[entity.pose]\nx = 1.0\n");
    try expectRefused(error.InvalidArgument, "[[entity]]\nname = \"P\"\ntype = \"pong.paddle\"\n[entity.paddle]\nwidth = 1.0\n");
    try expectRefused(error.InvalidArgument, "[[entity]]\nname = \"P\"\ntype = \"pong.paddle\"\n[entity.paddle]\nspeed = \"fast\"\n");
}

test "a type never registered is not found" {
    try expectRefused(error.NotFound, "[[entity]]\nname = \"G\"\ntype = \"ghost\"\n");
}

test "a connection, or an entry naming both a scene and a type, is refused" {
    try expectRefused(error.InvalidArgument, "[[entity]]\nname = \"B\"\n[[entity.connect]]\nsignal = \"Goal\"\ntarget = \"B\"\n");
    try expectRefused(error.InvalidArgument, "[[entity]]\nname = \"B\"\ntype = \"pong.paddle\"\nscene = \"other.scene.toml\"\n");
}

test "a missing file is not found and an entry without a name is refused" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    try testing.expectEqual(R.code(error.NotFound), f.instantiate("/scenes/missing.scene.toml", invalid));
    try expectRefused(error.InvalidArgument, "[[entity]]\ntype = \"pong.paddle\"\n");
}

test "the scene files leak nothing" {
    try heap.expectNoLeaks();
}
