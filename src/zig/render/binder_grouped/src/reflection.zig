//! Reads the reflection the build writes beside each compiled shader, and answers each group of it
//! as bind group layout entries and as bind group entries matched by name.

const std = @import("std");
const c = @import("c");
const gpa = @import("heap").gpa;

const JBinding = struct {
    kind: []const u8,
    index: u32 = 0,
    space: u32 = 0,
};

const JContainer = struct {
    binding: ?JBinding = null,
    bindings: []const JBinding = &.{},
};

const JField = struct {
    name: []const u8,
    type: JType,
    binding: ?JBinding = null,
};

const JType = struct {
    kind: []const u8,
    baseShape: ?[]const u8 = null,
    access: ?[]const u8 = null,
    elementType: ?*const JType = null,
    fields: ?[]const JField = null,
    containerVarLayout: ?JContainer = null,
};

const JParameter = struct {
    name: []const u8,
    binding: JBinding,
    type: JType,
};

const JReflection = struct {
    parameters: []const JParameter = &.{},
};

pub const Binding = struct {
    name: []const u8,
    binding: u32,
    type: c.ke_gpu_binding_type,
    view_dimension: c.ke_gpu_texture_dimension,
    stages: u32,
    has_dynamic_offset: bool = false,
};

/// The space the compiler places every parameter declared outside a block in.
const loose_space: u32 = 0;

pub const ReadError = error{ OutOfMemory, Malformed, LooseUniform, MismatchedGroup };

/// One group of a shader, gathered from the reflection of one or more stages. The names of its
/// bindings live in the group's arena, so the group is released as a whole by `deinit`.
pub const Group = struct {
    arena: std.heap.ArenaAllocator,
    index: ?u32 = null,
    bindings: std.ArrayList(Binding) = .empty,

    pub fn init(allocator: std.mem.Allocator) Group {
        return .{ .arena = .init(allocator) };
    }

    pub fn deinit(self: *Group) void {
        self.arena.deinit();
    }

    pub fn find(self: *Group, name: []const u8) ?*Binding {
        for (self.bindings.items) |*b| {
            if (std.mem.eql(u8, b.name, name)) return b;
        }
        return null;
    }

    /// Adds what the reflection `json` of `stage` declares for `block`, or for the parameters
    /// declared outside any block when `block` is null, merging the stages of a binding seen before. Returns whether the
    /// reflection declares the block; the loose parameters are always declared.
    pub fn collect(self: *Group, json: []const u8, block: ?[]const u8, stage: u32) ReadError!bool {
        const a = self.arena.allocator();
        const parsed = std.json.parseFromSliceLeaky(JReflection, a, json, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Malformed,
        };
        if (block) |name| {
            for (parsed.parameters) |p| {
                if (!std.mem.eql(u8, p.name, name)) continue;
                if (!std.mem.eql(u8, p.type.kind, "parameterBlock")) return error.Malformed;
                try self.setIndex(p.binding.index);
                const element = p.type.elementType orelse return error.Malformed;
                const container = p.type.containerVarLayout orelse JContainer{};
                const single: [1]JBinding = .{container.binding orelse JBinding{ .kind = "" }};
                for ([_][]const JBinding{ container.bindings, &single }) |list| {
                    for (list) |cb| {
                        if (std.mem.eql(u8, cb.kind, "descriptorTableSlot")) {
                            try self.add(.{ .name = name, .binding = cb.index, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .view_dimension = 0, .stages = stage });
                        }
                    }
                }
                for (element.fields orelse &.{}) |f| {
                    const fb = f.binding orelse continue;
                    if (!std.mem.eql(u8, fb.kind, "descriptorTableSlot")) continue;
                    try self.add(try bindingOf(f.name, fb.index, f.type, stage));
                }
                return true;
            }
            return false;
        }
        try self.setIndex(loose_space);
        for (parsed.parameters) |p| {
            if (std.mem.eql(u8, p.binding.kind, "uniform")) return error.LooseUniform;
            if (!std.mem.eql(u8, p.binding.kind, "descriptorTableSlot")) continue;
            if (p.binding.space != loose_space) continue;
            try self.add(try bindingOf(p.name, p.binding.index, p.type, stage));
        }
        return true;
    }

    fn setIndex(self: *Group, index: u32) ReadError!void {
        if (self.index) |known| {
            if (known != index) return error.MismatchedGroup;
        }
        self.index = index;
    }

    fn add(self: *Group, binding: Binding) ReadError!void {
        if (self.find(binding.name)) |known| {
            if (known.binding != binding.binding) return error.MismatchedGroup;
            known.stages |= binding.stages;
            return;
        }
        const a = self.arena.allocator();
        var owned = binding;
        owned.name = try a.dupe(u8, binding.name);
        try self.bindings.append(a, owned);
    }
};

fn bindingOf(name: []const u8, index: u32, t: JType, stage: u32) ReadError!Binding {
    var b = Binding{ .name = name, .binding = index, .type = c.KE_GPU_BINDING_TYPE_BUFFER, .view_dimension = 0, .stages = stage };
    const read_write = if (t.access) |acc| std.mem.eql(u8, acc, "readWrite") else false;
    if (std.mem.eql(u8, t.kind, "constantBuffer")) return b;
    if (std.mem.eql(u8, t.kind, "samplerState")) {
        b.type = c.KE_GPU_BINDING_TYPE_SAMPLER;
        return b;
    }
    if (!std.mem.eql(u8, t.kind, "resource")) return error.Malformed;
    const shape = t.baseShape orelse return error.Malformed;
    if (std.mem.eql(u8, shape, "structuredBuffer") or std.mem.eql(u8, shape, "byteAddressBuffer")) {
        b.type = if (read_write) c.KE_GPU_BINDING_TYPE_STORAGE_BUFFER else c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER;
        return b;
    }
    if (std.mem.eql(u8, shape, "texture2D")) {
        b.type = if (read_write) c.KE_GPU_BINDING_TYPE_STORAGE_TEXTURE else c.KE_GPU_BINDING_TYPE_TEXTURE;
        return b;
    }
    if (std.mem.eql(u8, shape, "textureCube")) {
        b.type = c.KE_GPU_BINDING_TYPE_TEXTURE;
        b.view_dimension = c.KE_GPU_TEXTURE_DIM_CUBE;
        return b;
    }
    return error.Malformed;
}

fn fail(out_error: [*c][*c]c.ke_error, kind: *const c.ke_error_type, message: [*c]const u8, src: std.builtin.SourceLocation) void {
    c.ke_error_set(out_error, kind, message, src.file, @intCast(src.line), null);
}

/// A resource a binder was given for every parameter of `name` a set leaves out.
pub const Provided = struct {
    name: [:0]const u8,
    binding: c.ke_render_shader_binding,
};

/// The names of the parameter blocks the reflection `json` declares, allocated in `a`.
pub fn blockNames(a: std.mem.Allocator, json: []const u8) ReadError![]const []const u8 {
    const parsed = std.json.parseFromSliceLeaky(JReflection, a, json, .{ .ignore_unknown_fields = true }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.Malformed,
    };
    var names: std.ArrayList([]const u8) = .empty;
    for (parsed.parameters) |p| {
        if (std.mem.eql(u8, p.type.kind, "parameterBlock")) try names.append(a, p.name);
    }
    return names.items;
}

/// A layout with one entry per binding of `group`, each visible to the stages that declare it.
/// The invalid handle with the error filled when the entries cannot be allocated or the device
/// refuses the layout.
pub fn createLayout(dev: *c.ke_gpu_device, group: *const Group, label: [*c]const u8, out_error: [*c][*c]c.ke_error) c.ke_gpu_bind_group_layout {
    const entries = gpa.alloc(c.ke_gpu_bind_group_layout_entry, group.bindings.items.len) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "shader group: entry allocation failed", @src());
        return c.KE_GPU_INVALID_HANDLE;
    };
    defer gpa.free(entries);
    for (group.bindings.items, entries) |b, *e| {
        e.* = .{
            .binding = b.binding,
            .visibility = b.stages,
            .type = b.type,
            .has_dynamic_offset = b.has_dynamic_offset,
            .view_dimension = b.view_dimension,
        };
    }
    const layout = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .label = label,
        .entry_count = @intCast(entries.len),
        .entries = entries.ptr,
    }, out_error);
    return layout;
}

/// The bind group entries for `bindings` in the group's numbering, plus one for each parameter of
/// the group they leave out that `provided` names, owned by the caller. Null with the error
/// filled when a binding names no parameter, a parameter is bound twice, or one is left unbound.
pub fn matchBindings(group: *Group, bindings: []const c.ke_render_shader_binding, provided: []const Provided, out_error: [*c][*c]c.ke_error) ?[]c.ke_gpu_bind_group_entry {
    const entries = gpa.alloc(c.ke_gpu_bind_group_entry, group.bindings.items.len) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_set: entry allocation failed", @src());
        return null;
    };
    const bound = gpa.alloc(bool, group.bindings.items.len) catch {
        gpa.free(entries);
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_set: entry allocation failed", @src());
        return null;
    };
    defer gpa.free(bound);
    @memset(bound, false);
    for (bindings) |src| {
        const slot = if (src.name != null) indexOf(group, std.mem.span(src.name)) else null;
        const i = slot orelse {
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_set: a binding names no parameter of the group", @src());
            gpa.free(entries);
            return null;
        };
        if (bound[i]) {
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_set: a parameter is bound twice", @src());
            gpa.free(entries);
            return null;
        }
        bound[i] = true;
        entries[i] = entryOf(group.bindings.items[i], src);
    }
    for (group.bindings.items, bound, entries) |b, was_bound, *e| {
        if (was_bound) continue;
        const given = providedFor(provided, b.name) orelse {
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_set: a parameter of the group has no binding", @src());
            gpa.free(entries);
            return null;
        };
        e.* = entryOf(b, given);
    }
    return entries;
}

fn providedFor(provided: []const Provided, name: []const u8) ?c.ke_render_shader_binding {
    for (provided) |p| {
        if (std.mem.eql(u8, p.name, name)) return p.binding;
    }
    return null;
}

fn indexOf(group: *Group, name: []const u8) ?usize {
    for (group.bindings.items, 0..) |b, i| {
        if (std.mem.eql(u8, b.name, name)) return i;
    }
    return null;
}

fn entryOf(b: Binding, src: c.ke_render_shader_binding) c.ke_gpu_bind_group_entry {
    return .{
        .binding = b.binding,
        .type = b.type,
        .buffer = src.buffer,
        .buffer_offset = src.buffer_offset,
        .buffer_size = src.buffer_size,
        .texture_view = src.texture_view,
        .sampler = src.sampler,
    };
}

const forward_like_json =
    \\{"parameters":[
    \\ {"name":"mat","binding":{"kind":"subElementRegisterSpace","index":1},
    \\  "type":{"kind":"parameterBlock","elementType":{"kind":"struct","fields":[
    \\   {"name":"base","type":{"kind":"vector"},"binding":{"kind":"uniform","offset":0,"size":16}},
    \\   {"name":"albedo","type":{"kind":"resource","baseShape":"texture2D"},"binding":{"kind":"descriptorTableSlot","index":1}},
    \\   {"name":"smp","type":{"kind":"samplerState"},"binding":{"kind":"descriptorTableSlot","index":2}}]},
    \\  "containerVarLayout":{"bindings":[{"kind":"descriptorTableSlot","index":0},{"kind":"subElementRegisterSpace","index":0}]}}},
    \\ {"name":"shadow_map","binding":{"kind":"descriptorTableSlot","index":1},"type":{"kind":"resource","baseShape":"texture2D"}},
    \\ {"name":"ibl_env","binding":{"kind":"descriptorTableSlot","index":3},"type":{"kind":"resource","baseShape":"textureCube"}},
    \\ {"name":"lights","binding":{"kind":"descriptorTableSlot","index":4},"type":{"kind":"resource","baseShape":"structuredBuffer"}},
    \\ {"name":"counts","binding":{"kind":"descriptorTableSlot","index":5},"type":{"kind":"resource","baseShape":"structuredBuffer","access":"readWrite"}}
    \\]}
;

test "the loose parameters of a shader are its group zero, numbered and typed as the reflection declares" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    try std.testing.expect(try group.collect(forward_like_json, null, c.KE_GPU_SHADER_STAGE_FRAGMENT));
    try std.testing.expectEqual(@as(?u32, 0), group.index);
    try std.testing.expectEqual(@as(usize, 4), group.bindings.items.len);
    try std.testing.expectEqual(@as(u32, 3), group.find("ibl_env").?.binding);
    try std.testing.expectEqual(@as(c.ke_gpu_texture_dimension, c.KE_GPU_TEXTURE_DIM_CUBE), group.find("ibl_env").?.view_dimension);
    try std.testing.expectEqual(@as(c.ke_gpu_binding_type, c.KE_GPU_BINDING_TYPE_READONLY_STORAGE_BUFFER), group.find("lights").?.type);
    try std.testing.expectEqual(@as(c.ke_gpu_binding_type, c.KE_GPU_BINDING_TYPE_STORAGE_BUFFER), group.find("counts").?.type);
}

test "a parameter block is its own group, its uniform data bound under the block's name" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    try std.testing.expect(try group.collect(forward_like_json, "mat", c.KE_GPU_SHADER_STAGE_FRAGMENT));
    try std.testing.expectEqual(@as(?u32, 1), group.index);
    try std.testing.expectEqual(@as(u32, 0), group.find("mat").?.binding);
    try std.testing.expectEqual(@as(u32, 1), group.find("albedo").?.binding);
    try std.testing.expectEqual(@as(c.ke_gpu_binding_type, c.KE_GPU_BINDING_TYPE_SAMPLER), group.find("smp").?.type);
    try std.testing.expect(group.find("shadow_map") == null);
}

test "a block holding only uniform data is one buffer named after the block" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    const json =
        \\{"parameters":[{"name":"object","binding":{"kind":"subElementRegisterSpace","index":2},
        \\ "type":{"kind":"parameterBlock","elementType":{"kind":"struct","fields":[
        \\  {"name":"mvp","type":{"kind":"matrix"},"binding":{"kind":"uniform","offset":0,"size":64}}]},
        \\  "containerVarLayout":{"binding":{"kind":"descriptorTableSlot","index":0}}}}]}
    ;
    try std.testing.expect(try group.collect(json, "object", c.KE_GPU_SHADER_STAGE_VERTEX));
    try std.testing.expectEqual(@as(?u32, 2), group.index);
    try std.testing.expectEqual(@as(usize, 1), group.bindings.items.len);
    try std.testing.expectEqual(@as(u32, 0), group.find("object").?.binding);
}

test "a block no stage declares is reported as absent" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    try std.testing.expect(!try group.collect(forward_like_json, "object", c.KE_GPU_SHADER_STAGE_VERTEX));
}

test "a binding declared by two stages is one entry visible to both" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    _ = try group.collect(forward_like_json, "mat", c.KE_GPU_SHADER_STAGE_VERTEX);
    _ = try group.collect(forward_like_json, "mat", c.KE_GPU_SHADER_STAGE_FRAGMENT);
    try std.testing.expectEqual(@as(usize, 3), group.bindings.items.len);
    try std.testing.expectEqual(@as(u32, c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT), group.find("albedo").?.stages);
}

test "a parameter bound explicitly to another space is not part of the loose group" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    const json =
        \\{"parameters":[
        \\ {"name":"frame","binding":{"kind":"descriptorTableSlot","index":0},"type":{"kind":"constantBuffer"}},
        \\ {"name":"obj","binding":{"kind":"descriptorTableSlot","index":0,"space":2},"type":{"kind":"constantBuffer"}}]}
    ;
    try std.testing.expect(try group.collect(json, null, c.KE_GPU_SHADER_STAGE_VERTEX));
    try std.testing.expectEqual(@as(usize, 1), group.bindings.items.len);
    try std.testing.expect(group.find("obj") == null);
}

test "a loose uniform outside any buffer or block is refused" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    const json =
        \\{"parameters":[{"name":"tint","binding":{"kind":"uniform","offset":0,"size":16},"type":{"kind":"vector"}}]}
    ;
    try std.testing.expectError(error.LooseUniform, group.collect(json, null, c.KE_GPU_SHADER_STAGE_FRAGMENT));
}

test "a parameter the binder was given is bound to it when the set leaves it out" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    const json =
        \\{"parameters":[
        \\ {"name":"ke_frame","binding":{"kind":"descriptorTableSlot","index":0},"type":{"kind":"constantBuffer"}},
        \\ {"name":"ke_samp_linear","binding":{"kind":"descriptorTableSlot","index":1},"type":{"kind":"samplerState"}},
        \\ {"name":"own","binding":{"kind":"descriptorTableSlot","index":2},"type":{"kind":"constantBuffer"}}]}
    ;
    _ = try group.collect(json, null, c.KE_GPU_SHADER_STAGE_FRAGMENT);
    const zero = std.mem.zeroes(c.ke_render_shader_binding);
    var frame = zero;
    frame.buffer = 11;
    var linear = zero;
    linear.sampler = 12;
    const globals = [_]Provided{ .{ .name = "ke_frame", .binding = frame }, .{ .name = "ke_samp_linear", .binding = linear } };
    var err: [*c]c.ke_error = null;
    const own = [_]c.ke_render_shader_binding{.{ .name = "own", .buffer = 13, .buffer_offset = 0, .buffer_size = 16, .texture_view = 0, .sampler = 0 }};
    const entries = matchBindings(&group, &own, &globals, &err).?;
    defer gpa.free(entries);
    try std.testing.expectEqual(@as(c.ke_gpu_buffer, 11), entries[0].buffer);
    try std.testing.expectEqual(@as(c.ke_gpu_sampler, 12), entries[1].sampler);
    try std.testing.expectEqual(@as(c.ke_gpu_buffer, 13), entries[2].buffer);
}

test "bindings are placed at their parameters' numbers, and a name the group lacks is refused" {
    var group = Group.init(std.testing.allocator);
    defer group.deinit();
    _ = try group.collect(forward_like_json, "mat", c.KE_GPU_SHADER_STAGE_FRAGMENT);
    var err: [*c]c.ke_error = null;
    const ok = [_]c.ke_render_shader_binding{
        .{ .name = "smp", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = 7 },
        .{ .name = "mat", .buffer = 3, .buffer_offset = 0, .buffer_size = 16, .texture_view = 0, .sampler = 0 },
        .{ .name = "albedo", .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 5, .sampler = 0 },
    };
    const globals = [_]Provided{};
    const entries = matchBindings(&group, &ok, &globals, &err).?;
    defer gpa.free(entries);
    try std.testing.expectEqual(@as(c.ke_gpu_buffer, 3), entries[0].buffer);
    try std.testing.expectEqual(@as(c.ke_gpu_binding_type, c.KE_GPU_BINDING_TYPE_TEXTURE), entries[1].type);
    try std.testing.expectEqual(@as(u32, 2), entries[2].binding);
    try std.testing.expectEqual(@as(c.ke_gpu_sampler, 7), entries[2].sampler);

    var wrong = ok;
    wrong[2].name = "albedo_map";
    try std.testing.expect(matchBindings(&group, &wrong, &globals, &err) == null);
    try std.testing.expect(err != null);
}

test "the blocks a shader declares are listed by name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const names = try blockNames(arena.allocator(), forward_like_json);
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualStrings("mat", names[0]);
}
