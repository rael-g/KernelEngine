//! A build step that lays a tool out under `build/tools`, from a package the build manifest
//! fetched, with what the package cannot carry: the executable bit, a file that must differ from the
//! one shipped, and a file added from outside the package.

const std = @import("std");

/// A file of the tool made from a file of the package by replacing `find`, which it must hold,
/// with `replace`.
pub const Patched = struct {
    from: []const u8,
    to: []const u8,
    find: []const u8,
    replace: []const u8,
};

/// A file of the tool copied from outside the package, such as one `fetch_file` downloaded, and
/// made executable.
pub const Added = struct {
    path: []const u8,
    source: std.Build.LazyPath,
};

/// What `create` lays out: the package tree copied into `dest`, the files under each of
/// `executable_dirs` made executable, then `patched` and `added`. `stamp` names the
/// layout; a `dest` whose stamp file holds it is left as it is.
pub const Options = struct {
    package: std.Build.LazyPath,
    dest: []const u8,
    stamp: []const u8,
    executable_dirs: []const []const u8 = &.{},
    patched: []const Patched = &.{},
    added: []const Added = &.{},
};

/// The step, its options and the package directory resolved when the step runs.
pub const ToolTree = struct {
    step: std.Build.Step,
    options: Options,

    pub fn create(b: *std.Build, name: []const u8, options: Options) *ToolTree {
        const self = b.allocator.create(ToolTree) catch @panic("OOM");
        self.* = .{
            .step = std.Build.Step.init(.{ .id = .custom, .name = name, .owner = b, .makeFn = make }),
            .options = options,
        };
        options.package.addStepDependencies(&self.step);
        for (options.added) |a| a.source.addStepDependencies(&self.step);
        return self;
    }
};

const stamp_file = ".ke-tool";

fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
    const self: *ToolTree = @fieldParentPtr("step", step);
    const b = step.owner;
    const io = b.graph.io;
    const o = self.options;
    const cwd = std.Io.Dir.cwd();

    const stamp_path = b.pathJoin(&.{ o.dest, stamp_file });
    if (cwd.readFileAlloc(io, stamp_path, b.allocator, .limited(256))) |recorded| {
        if (std.mem.eql(u8, recorded, o.stamp)) return;
    } else |_| {}

    cwd.deleteTree(io, o.dest) catch {};
    try cwd.createDirPath(io, o.dest);
    var dest = try cwd.openDir(io, o.dest, .{});
    defer dest.close(io);

    var source = try cwd.openDir(io, o.package.getPath2(b, step), .{ .iterate = true });
    defer source.close(io);
    var walker = try source.walk(b.allocator);
    defer walker.deinit();
    while (try walker.next(io)) |entry| {
        switch (entry.kind) {
            .directory => try dest.createDirPath(io, entry.path),
            .file => {
                try source.copyFile(entry.path, dest, entry.path, io, .{});
                if (isUnder(entry.path, o.executable_dirs)) try makeExecutable(io, dest, entry.path);
            },
            else => {},
        }
    }

    for (o.patched) |p| {
        const original = try dest.readFileAlloc(io, p.from, b.allocator, .limited(1024 * 1024));
        if (std.mem.indexOf(u8, original, p.find) == null) return step.fail("{s} no longer holds {s}", .{ p.from, p.find });
        const contents = try std.mem.replaceOwned(u8, b.allocator, original, p.find, p.replace);
        if (std.fs.path.dirname(p.to)) |dir| try dest.createDirPath(io, dir);
        try dest.writeFile(io, .{ .sub_path = p.to, .data = contents });
    }

    for (o.added) |a| {
        if (std.fs.path.dirname(a.path)) |dir| try dest.createDirPath(io, dir);
        try cwd.copyFile(a.source.getPath2(b, step), dest, a.path, io, .{});
        try makeExecutable(io, dest, a.path);
    }

    try cwd.writeFile(io, .{ .sub_path = stamp_path, .data = o.stamp });
}

fn isUnder(path: []const u8, dirs: []const []const u8) bool {
    for (dirs) |dir| {
        if (path.len > dir.len and std.mem.startsWith(u8, path, dir) and std.fs.path.isSep(path[dir.len])) return true;
    }
    return false;
}

fn makeExecutable(io: std.Io, dir: std.Io.Dir, path: []const u8) !void {
    if (@import("builtin").os.tag == .windows) return;
    var file = try dir.openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);
    try file.setPermissions(io, .fromMode(0o755));
}
