//! A composition source that reads a TOML file into an assembly through its composition slots: the instances
//! first, in the order the file declares them, then each instance's bindings and orders, then the defaults.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_assembly_toml").logFn };

const toml = @import("c");
const abi_assembly = @import("abi_assembly");
const abi_file_system = @import("abi_file_system");
const abi_result = @import("abi_result");
const abi_toml = @import("abi_assembly_toml_factory");

const heap = @import("heap");
const gpa = heap.gpa;

const R = @import("result").Result(.{});
const log = std.log.scoped(.assembly_toml);

const Assembly = abi_assembly.c.ke_assembly;
const Source = abi_assembly.c.ke_composition_source;
const SourceHandle = abi_assembly.c.ke_composition_source_handle;
const Table = ?*toml.toml_table_t;

/// The state behind the source the factory returns: the vtable and the borrowed file system every load reads
/// through; a load keeps nothing between calls.
const State = struct {
    api: Source,
    fs: *abi_file_system.c.ke_file_system,
};

/// The whole file at `path` with a terminating zero, owned by the caller; NotFound when there is no such file,
/// which is asked first so that its absence is not a failed read.
fn readText(fs: *abi_file_system.c.ke_file_system, path: [*c]const u8) R.Error![:0]u8 {
    var stat: abi_file_system.c.ke_file_stat = undefined;
    try R.check(fs.stat.?(fs, path, &stat));
    if (stat.kind != abi_file_system.c.KE_FILE_KIND_FILE) return error.NotFound;
    var file: ?*abi_file_system.c.ke_open_file = null;
    try R.check(fs.open.?(fs, path, &file));
    defer fs.close.?(fs, file);
    var size: u64 = 0;
    try R.check(fs.size.?(fs, file, &size));
    const text = try gpa.allocSentinel(u8, @intCast(size), 0);
    errdefer gpa.free(text);
    var done: usize = 0;
    while (done < text.len) {
        var read: usize = 0;
        try R.check(fs.read_at.?(fs, file, done, text.ptr + done, text.len - done, &read));
        if (read == 0) break;
        done += read;
    }
    return text[0..done :0];
}

/// A string the parser allocated, freed with `free`.
const Text = struct {
    ptr: [*c]u8,

    fn free(self: Text) void {
        std.c.free(self.ptr);
    }
};

fn refuse(comptime format: []const u8, args: anytype) R.Error {
    log.warn(format, args);
    return error.General;
}

fn stringIn(tab: Table, key: [*c]const u8, what: []const u8) R.Error!?Text {
    if (toml.toml_key_exists(tab, key) == 0) return null;
    const read = toml.toml_string_in(tab, key);
    if (read.ok == 0) return refuse("{s} {s} is not a string", .{ what, key });
    return .{ .ptr = read.u.s };
}

fn stringAt(arr: *toml.toml_array_t, index: c_int, what: []const u8) R.Error!Text {
    const read = toml.toml_string_at(arr, index);
    if (read.ok == 0) return refuse("{s}[{d}] is not a string", .{ what, index });
    return .{ .ptr = read.u.s };
}

/// Refuses a key of `tab` that `known` does not name.
fn onlyKeys(tab: Table, known: []const []const u8, what: []const u8) R.Error!void {
    var i: c_int = 0;
    while (toml.toml_key_in(tab, i)) |key| : (i += 1) {
        const name = std.mem.span(key);
        for (known) |k| {
            if (std.mem.eql(u8, k, name)) break;
        } else return refuse("{s} has the key {s}, which a composition does not know", .{ what, name });
    }
}

fn addInstance(a: *Assembly, name: [*c]const u8, tab: Table) R.Error!void {
    try onlyKeys(tab, &.{ "part", "section", "bind", "order" }, "an instance");
    const part = try stringIn(tab, "part", "part of") orelse return refuse("the instance {s} names no part", .{name});
    defer part.free();
    const section = try stringIn(tab, "section", "section of");
    defer if (section) |s| s.free();
    try R.check(a.add_instance.?(a, name, part.ptr, if (section) |s| s.ptr else null));
}

fn bindSlots(a: *Assembly, name: [*c]const u8, tab: Table) R.Error!void {
    const binds = toml.toml_table_in(tab, "bind") orelse {
        if (toml.toml_key_exists(tab, "bind") != 0) return refuse("bind of {s} is not a table", .{name});
        return;
    };
    var i: c_int = 0;
    while (toml.toml_key_in(binds, i)) |slot| : (i += 1) {
        if (toml.toml_array_in(binds, slot)) |targets| {
            var j: c_int = 0;
            while (j < toml.toml_array_nelem(targets)) : (j += 1) {
                const target = try stringAt(targets, j, "a binding");
                defer target.free();
                try R.check(a.bind.?(a, name, slot, target.ptr));
            }
        } else {
            const target = (try stringIn(binds, slot, "the binding")).?;
            defer target.free();
            try R.check(a.bind.?(a, name, slot, target.ptr));
        }
    }
}

fn orderTargets(a: *Assembly, name: [*c]const u8, tab: Table) R.Error!void {
    const order = toml.toml_array_in(tab, "order") orelse {
        if (toml.toml_key_exists(tab, "order") != 0) return refuse("order of {s} is not an array", .{name});
        return;
    };
    var previous: ?Text = null;
    defer if (previous) |p| p.free();
    var j: c_int = 0;
    while (j < toml.toml_array_nelem(order)) : (j += 1) {
        const then = try stringAt(order, j, "an order");
        if (previous) |first| {
            R.check(a.order.?(a, name, null, first.ptr, then.ptr)) catch |err| {
                then.free();
                return err;
            };
            first.free();
        }
        previous = then;
    }
}

fn setDefaults(a: *Assembly, root: Table) R.Error!void {
    const defaults = toml.toml_table_in(root, "defaults") orelse {
        if (toml.toml_key_exists(root, "defaults") != 0) return refuse("defaults is not a table", .{});
        return;
    };
    var i: c_int = 0;
    while (toml.toml_key_in(defaults, i)) |contract| : (i += 1) {
        const instance = (try stringIn(defaults, contract, "the default of")).?;
        defer instance.free();
        try R.check(a.set_default.?(a, contract, instance.ptr));
    }
}

fn compose(a: *Assembly, root: Table) R.Error!void {
    try onlyKeys(root, &.{ "instance", "defaults" }, "a composition");
    const instances = toml.toml_table_in(root, "instance");
    if (instances == null and toml.toml_key_exists(root, "instance") != 0) return refuse("instance is not a table", .{});
    var i: c_int = 0;
    while (toml.toml_key_in(instances, i)) |name| : (i += 1) {
        const tab = toml.toml_table_in(instances, name) orelse return refuse("the instance {s} is not a table", .{name});
        try addInstance(a, name, tab);
    }
    i = 0;
    while (toml.toml_key_in(instances, i)) |name| : (i += 1) {
        const tab = toml.toml_table_in(instances, name);
        try bindSlots(a, name, tab);
        try orderTargets(a, name, tab);
    }
    try setDefaults(a, root);
}

/// Slot `load`. A missing file is not found and is never opened; a parse error fails with general before any
/// call to the assembly, and the parser's message is logged; the first refused key or failed call stops the load,
/// and the calls before it stay.
fn load(self: [*c]Source, assembly: [*c]Assembly, path: [*c]const u8) callconv(.c) abi_result.c.ke_result {
    if (self == null or assembly == null or path == null) return R.code(error.InvalidArgument);
    const text = readText(stateOf(self).fs, path) catch |err| {
        log.warn("reading the composition {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    defer gpa.free(text);

    var errbuf: [256]u8 = std.mem.zeroes([256]u8);
    const root = toml.toml_parse(text.ptr, &errbuf, errbuf.len);
    if (root == null) {
        log.warn("{s} does not parse: {s}", .{ path, std.mem.sliceTo(&errbuf, 0) });
        return R.code(error.General);
    }
    defer toml.toml_free(root);

    compose(assembly, root) catch |err| {
        log.warn("loading the composition {s} failed: {t}", .{ path, err });
        return R.code(err);
    };
    return R.ok;
}

fn stateOf(self: [*c]Source) *State {
    return @fieldParentPtr("api", @as(*Source, @ptrCast(self)));
}

fn destroy(self: [*c]Source) callconv(.c) void {
    if (self == null) return;
    gpa.destroy(stateOf(self));
}

/// The factory. Fails with out of memory, leaving the handle zeroed, when the state cannot be allocated.
export fn ke_assembly_toml_create(fs_in: ?*abi_file_system.c.ke_file_system, out_source: ?*SourceHandle) callconv(.c) abi_result.c.ke_result {
    const out = out_source orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(SourceHandle);
    const fs = fs_in orelse return R.code(error.InvalidArgument);
    const s = gpa.create(State) catch {
        log.warn("creating the TOML composition source failed: out of memory", .{});
        return R.code(error.OutOfMemory);
    };
    s.* = .{ .api = std.mem.zeroes(Source), .fs = fs };
    s.api.handle = s;
    s.api.load = load;
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

const zsub = @import("zsub");

var served: ?[]const u8 = null;
var file_token: u8 = 0;
var calls: std.ArrayListUnmanaged([]u8) = .empty;
var refused_call: ?[]const u8 = null;

fn statServed(args: zsub.For(abi_file_system.c.ke_file_system).Args(.stat)) abi_result.c.ke_result {
    const text = served orelse return R.code(error.NotFound);
    args[2].?.* = .{ .kind = abi_file_system.c.KE_FILE_KIND_FILE, .size = text.len };
    return R.ok;
}

fn openServed(args: zsub.For(abi_file_system.c.ke_file_system).Args(.open)) abi_result.c.ke_result {
    args[2].?.* = @ptrCast(&file_token);
    return R.ok;
}

fn sizeServed(args: zsub.For(abi_file_system.c.ke_file_system).Args(.size)) abi_result.c.ke_result {
    args[2].?.* = served.?.len;
    return R.ok;
}

fn readServed(args: zsub.For(abi_file_system.c.ke_file_system).Args(.read_at)) abi_result.c.ke_result {
    const text = served.?;
    const from: usize = @intCast(args[2]);
    const n = @min(args[4], text.len - from);
    @memcpy(@as([*]u8, @ptrCast(args[3].?))[0..n], text[from..][0..n]);
    args[5].?.* = n;
    return R.ok;
}

fn closeServed(_: zsub.For(abi_file_system.c.ke_file_system).Args(.close)) void {}

fn opt(s: [*c]const u8) []const u8 {
    return if (s == null) "-" else std.mem.span(s);
}

fn record(comptime format: []const u8, args: anytype) abi_result.c.ke_result {
    const line = std.fmt.allocPrint(gpa, format, args) catch unreachable;
    if (refused_call) |refused| if (std.mem.eql(u8, refused, line)) {
        gpa.free(line);
        return R.code(error.NotFound);
    };
    calls.append(gpa, line) catch unreachable;
    return R.ok;
}

fn addInstanceRecorded(args: zsub.For(Assembly).Args(.add_instance)) abi_result.c.ke_result {
    return record("instance {s} {s} {s}", .{ opt(args[1]), opt(args[2]), opt(args[3]) });
}

fn bindRecorded(args: zsub.For(Assembly).Args(.bind)) abi_result.c.ke_result {
    return record("bind {s} {s} {s}", .{ opt(args[1]), opt(args[2]), opt(args[3]) });
}

fn orderRecorded(args: zsub.For(Assembly).Args(.order)) abi_result.c.ke_result {
    return record("order {s} {s} {s} {s}", .{ opt(args[1]), opt(args[2]), opt(args[3]), opt(args[4]) });
}

fn defaultRecorded(args: zsub.For(Assembly).Args(.set_default)) abi_result.c.ke_result {
    return record("default {s} {s}", .{ opt(args[1]), opt(args[2]) });
}

fn clearCalls() void {
    for (calls.items) |line| gpa.free(line);
    calls.clearAndFree(gpa);
    refused_call = null;
}

/// Loads `text` (no file when null) into a substitute assembly that records each call, and returns the code.
fn testLoad(text: ?[]const u8) !abi_result.c.ke_result {
    served = text;
    var fs_sub: zsub.For(abi_file_system.c.ke_file_system) = undefined;
    try fs_sub.init();
    defer fs_sub.deinit();
    _ = fs_sub.when(.stat).does(statServed);
    _ = fs_sub.when(.open).does(openServed);
    _ = fs_sub.when(.size).does(sizeServed);
    _ = fs_sub.when(.read_at).does(readServed);
    _ = fs_sub.when(.close).does(closeServed);
    var a_sub: zsub.For(Assembly) = undefined;
    try a_sub.init();
    defer a_sub.deinit();
    _ = a_sub.when(.add_instance).does(addInstanceRecorded);
    _ = a_sub.when(.bind).does(bindRecorded);
    _ = a_sub.when(.order).does(orderRecorded);
    _ = a_sub.when(.set_default).does(defaultRecorded);
    var h: SourceHandle = undefined;
    try R.check(ke_assembly_toml_create(fs_sub.api(), &h));
    defer h.destroy.?(h.ref);
    const loaded = h.ref.?.load.?(h.ref, a_sub.api(), "composition");
    if (text == null) try fs_sub.received(.open).never();
    return loaded;
}

fn expectCalls(expected: []const []const u8) !void {
    try std.testing.expectEqual(expected.len, calls.items.len);
    for (expected, calls.items) |e, c| try std.testing.expectEqualStrings(e, c);
}

test "a composition adds its instances in order, then their bindings and orders, then the defaults" {
    defer clearCalls();
    const text =
        \\[defaults]
        \\ke_ecs = "world"
        \\
        \\[instance.world]
        \\part = "ecs_flecs"
        \\section = "ecs"
        \\
        \\[instance.input]
        \\part = "input_default"
        \\
        \\[instance.layout]
        \\part = "scheduler_layout"
        \\order = ["startup", "update", "shutdown"]
        \\bind = { startup = "startup", every_tick = ["update", "render"] }
        \\
    ;
    try std.testing.expectEqual(R.ok, try testLoad(text));
    try expectCalls(&.{
        "instance world ecs_flecs ecs",
        "instance input input_default -",
        "instance layout scheduler_layout -",
        "bind layout startup startup",
        "bind layout every_tick update",
        "bind layout every_tick render",
        "order layout - startup update",
        "order layout - update shutdown",
        "default ke_ecs world",
    });
}

test "a missing file is not found and is never opened" {
    defer clearCalls();
    try std.testing.expectError(error.NotFound, R.check(try testLoad(null)));
    try expectCalls(&.{});
}

test "a file that does not parse fails with general before any call" {
    defer clearCalls();
    try std.testing.expectError(error.General, R.check(try testLoad("this is = = not toml\n")));
    try expectCalls(&.{});
}

test "an instance that names no part is refused" {
    defer clearCalls();
    try std.testing.expectError(error.General, R.check(try testLoad("[instance.world]\nsection = \"ecs\"\n")));
    try expectCalls(&.{});
}

test "a key a composition does not know is refused" {
    defer clearCalls();
    try std.testing.expectError(error.General, R.check(try testLoad("[instance.world]\npart = \"ecs_flecs\"\nsettings = \"ecs\"\n")));
    try std.testing.expectError(error.General, R.check(try testLoad("[parts]\nx = 1\n")));
}

test "a binding that is not a string is refused" {
    defer clearCalls();
    try std.testing.expectError(error.General, R.check(try testLoad("[instance.a]\npart = \"p\"\nbind = { slot = 3 }\n")));
}

test "a call the assembly refuses stops the load with its code, and the calls before it stay" {
    defer clearCalls();
    refused_call = "bind a first x";
    const text =
        \\[instance.a]
        \\part = "p"
        \\bind = { first = "x", second = "y" }
        \\
    ;
    try std.testing.expectError(error.NotFound, R.check(try testLoad(text)));
    try expectCalls(&.{"instance a p -"});
}

test "null arguments are refused" {
    var fs_sub: zsub.For(abi_file_system.c.ke_file_system) = undefined;
    try fs_sub.init();
    defer fs_sub.deinit();
    var none: SourceHandle = undefined;
    try std.testing.expectError(error.InvalidArgument, R.check(ke_assembly_toml_create(null, &none)));
    try std.testing.expectError(error.InvalidArgument, R.check(ke_assembly_toml_create(fs_sub.api(), null)));
    var h: SourceHandle = undefined;
    try R.check(ke_assembly_toml_create(fs_sub.api(), &h));
    defer h.destroy.?(h.ref);
    var assembly = std.mem.zeroes(Assembly);
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(null, &assembly, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(h.ref, null, "x")));
    try std.testing.expectError(error.InvalidArgument, R.check(h.ref.?.load.?(h.ref, &assembly, null)));
}

test "loading a composition and clearing the recorded calls leaves no block allocated" {
    _ = try testLoad("[instance.a]\npart = \"p\"\norder = [\"x\", \"y\"]\nbind = { s = [\"x\", \"y\"] }\n");
    clearCalls();
    try heap.expectNoLeaks();
}
