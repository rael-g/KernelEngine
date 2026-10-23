//! The grouped resource binder: every group a shader declares is one bind group, and every material
//! is one bind group of its own, behind the one factory the plugin exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_binder_grouped").logFn };

const c = @import("c");
const R = @import("result").Result(c, .{});
const log = std.log.scoped(.binder_grouped);
const heap = @import("heap");
const gpa = heap.gpa;
const reflection = @import("reflection.zig");
const shader_files = @import("shader_files").ShaderFiles(c);

const material_block = "mat";
const material_sampler = "tex_sampler";
const material_sampler_source = "ke_samp_linear";

/// The uniform data of the `mat` block, laid out as the material shaders declare it.
const MaterialUniform = extern struct {
    base_color: [4]f32,
    metallic: f32,
    roughness: f32,
    alpha_cutoff: f32,
    ior: f32,
    distortion_strength: f32,
    pad: [3]f32 = .{ 0, 0, 0 },
};

const stage_suffixes = [_]struct { bit: u32, suffix: []const u8 }{
    .{ .bit = c.KE_GPU_SHADER_STAGE_VERTEX, .suffix = "vs" },
    .{ .bit = c.KE_GPU_SHADER_STAGE_FRAGMENT, .suffix = "fs" },
    .{ .bit = c.KE_GPU_SHADER_STAGE_COMPUTE, .suffix = "cs" },
};

/// The state behind a binder vtable. `provided` holds the resources `provide` was given, each name
/// owned by the state; `material_group` and `material_layout` describe the `mat` block every
/// material shader shares, read from the reflection the build embedded.
const State = struct {
    api: c.ke_render_resource_binder,
    device: *c.ke_gpu_device,
    shader_dir: []u8,
    provided: std.ArrayList(reflection.Provided),
    material_group: reflection.Group,
    material_layout: c.ke_gpu_bind_group_layout,
};

/// One group of a shader layout: the block it holds, null for the loose parameters, the bindings
/// read from the reflection and the layout built from them, which the binder's material layout is
/// for the material block and is then not owned.
const GroupLayout = struct {
    block: ?[]u8,
    group: reflection.Group,
    layout: c.ke_gpu_bind_group_layout,
    owned: bool,
};

/// What a `ke_render_shader_layout` points at: the groups of one shader and the index of its
/// material group, if it declares one.
const ShaderLayout = struct {
    groups: std.ArrayList(GroupLayout),
    material_index: ?u32,
};

/// What a `ke_render_resource_set` points at.
const Set = struct {
    index: u32,
    bind_group: c.ke_gpu_bind_group,
};

/// What a `ke_render_material_binding` points at.
const Material = struct {
    uniform: c.ke_gpu_buffer,
    bind_group: c.ke_gpu_bind_group,
};

fn stateOf(self: [*c]c.ke_render_resource_binder) *State {
    return @alignCast(@ptrCast(self.*.handle));
}

fn handleOf(ptr: anytype) u64 {
    return @intFromPtr(ptr);
}

fn pointed(comptime T: type, h: u64) ?*T {
    if (h == c.KE_RENDER_BINDING_INVALID) return null;
    return @ptrFromInt(h);
}

fn sameBlock(a: ?[]const u8, b: ?[]const u8) bool {
    if (a == null or b == null) return a == null and b == null;
    return std.mem.eql(u8, a.?, b.?);
}

fn findGroup(sl: *ShaderLayout, block: ?[]const u8) ?*GroupLayout {
    for (sl.groups.items) |*g| {
        if (sameBlock(g.block, block)) return g;
    }
    return null;
}

fn releaseShaderLayout(dev: *c.ke_gpu_device, sl: *ShaderLayout) void {
    for (sl.groups.items) |*g| {
        if (g.owned and g.layout != c.KE_GPU_INVALID_HANDLE) dev.destroy_bind_group_layout.?(dev, g.layout);
        if (g.block) |b| gpa.free(b);
        g.group.deinit();
    }
    sl.groups.deinit(gpa);
    gpa.destroy(sl);
}

/// The binder's `provide` slot: a binding under a name given before replaces the earlier one.
fn provide(self: [*c]c.ke_render_resource_binder, binding: [*c]const c.ke_render_shader_binding) callconv(.c) c.ke_result {
    if (self == null or binding == null or binding.*.name == null) return R.code(error.InvalidArgument);
    return R.of(keep(stateOf(self), binding.*));
}

fn keep(st: *State, binding: c.ke_render_shader_binding) R.Error!void {
    const name = std.mem.span(binding.name);
    for (st.provided.items) |*p| {
        if (std.mem.eql(u8, p.name, name)) {
            p.binding = binding;
            p.binding.name = p.name.ptr;
            return;
        }
    }
    const owned = try gpa.dupeZ(u8, name);
    errdefer gpa.free(owned);
    var kept = binding;
    kept.name = owned.ptr;
    try st.provided.append(gpa, .{ .name = owned, .binding = kept });
}

/// Adds to `sl` a group for the loose parameters and for each block the reflection `json` of
/// `stage` declares, then reads every group's bindings from it.
fn collectStage(sl: *ShaderLayout, json: []const u8, stage: u32) R.Error!void {
    var names_arena = std.heap.ArenaAllocator.init(gpa);
    defer names_arena.deinit();
    const names = reflection.blockNames(names_arena.allocator(), json) catch |err| return readFailed(err);
    if (findGroup(sl, null) == null) try addGroup(sl, null);
    for (names) |name| {
        if (findGroup(sl, name) == null) try addGroup(sl, name);
    }
    for (sl.groups.items) |*g| {
        _ = g.group.collect(json, g.block, stage) catch |err| return readFailed(err);
    }
}

fn addGroup(sl: *ShaderLayout, block: ?[]const u8) R.Error!void {
    const owned: ?[]u8 = if (block) |b| try gpa.dupe(u8, b) else null;
    errdefer if (owned) |o| gpa.free(o);
    try sl.groups.append(gpa, .{ .block = owned, .group = reflection.Group.init(gpa), .layout = c.KE_GPU_INVALID_HANDLE, .owned = false });
}

fn readFailed(err: reflection.ReadError) R.Error {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    log.warn("create_shader_layout: {s}", .{switch (err) {
        error.OutOfMemory => unreachable,
        error.Malformed => "the reflection declares a parameter it cannot read",
        error.LooseUniform => "the shader declares a loose uniform outside any buffer or block",
        error.MismatchedGroup => "the stages place a parameter at different bindings",
    }});
    return error.InvalidArgument;
}

/// Drops the loose group when the shader declares no loose parameter, applies the hints, and
/// builds each group's layout, the material block taking the binder's.
fn finishLayout(st: *State, sl: *ShaderLayout, params: *const c.ke_render_shader_layout_params) R.Error!void {
    var i: usize = 0;
    while (i < sl.groups.items.len) {
        const g = &sl.groups.items[i];
        if (g.block == null and g.group.bindings.items.len == 0) {
            g.group.deinit();
            _ = sl.groups.orderedRemove(i);
            continue;
        }
        i += 1;
    }
    for (0..params.hint_count) |h| {
        const hint = params.hints[h];
        var found = false;
        for (sl.groups.items) |*g| {
            const b = g.group.find(std.mem.span(hint.name)) orelse continue;
            if (hint.flags & c.KE_RENDER_BINDING_HINT_DEPTH != 0) b.type = c.KE_GPU_BINDING_TYPE_DEPTH_TEXTURE;
            if (hint.flags & c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET != 0) b.has_dynamic_offset = true;
            found = true;
        }
        if (!found) {
            log.warn("create_shader_layout: the hint {s} names no parameter of the shader {s}", .{ std.mem.span(hint.name), std.mem.span(params.shader) });
            return error.InvalidArgument;
        }
    }
    for (sl.groups.items, 0..) |*g, gi| {
        const index = g.group.index orelse 0;
        for (sl.groups.items[0..gi]) |earlier| {
            if ((earlier.group.index orelse 0) == index) {
                log.warn("create_shader_layout: two groups of the shader {s} share the index {d}", .{ std.mem.span(params.shader), index });
                return error.InvalidArgument;
            }
        }
        if (g.block != null and std.mem.eql(u8, g.block.?, material_block)) {
            g.layout = st.material_layout;
            sl.material_index = index;
            continue;
        }
        g.layout = try reflection.createLayout(st.device, &g.group, params.shader);
        g.owned = true;
    }
}

/// The binder's `create_shader_layout` slot: reads "<shader dir>/<shader>.<vs|fs|cs>.json" for
/// each stage of the params.
fn createShaderLayout(self: [*c]c.ke_render_resource_binder, params: [*c]const c.ke_render_shader_layout_params, out_layout: [*c]c.ke_render_shader_layout) callconv(.c) c.ke_result {
    const out = out_layout orelse return R.code(error.InvalidArgument);
    out.* = c.KE_RENDER_BINDING_INVALID;
    if (self == null or params == null or params.*.shader == null or params.*.stages == 0) return R.code(error.InvalidArgument);
    const sl = shaderLayout(stateOf(self), params) catch |err| return R.code(err);
    out.* = handleOf(sl);
    return R.ok;
}

fn shaderLayout(st: *State, params: *const c.ke_render_shader_layout_params) R.Error!*ShaderLayout {
    const sl = try gpa.create(ShaderLayout);
    sl.* = .{ .groups = .empty, .material_index = null };
    errdefer releaseShaderLayout(st.device, sl);
    for (stage_suffixes) |s| {
        if (params.stages & s.bit == 0) continue;
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}.{s}.json", .{ st.shader_dir, std.mem.span(params.shader), s.suffix }) catch {
            log.warn("create_shader_layout: the reflection path of {s} is too long", .{std.mem.span(params.shader)});
            return error.InvalidArgument;
        };
        const json = try shader_files.read(gpa, path);
        defer gpa.free(json);
        try collectStage(sl, json, s.bit);
    }
    try finishLayout(st, sl, params);
    return sl;
}

/// The binder's `destroy_shader_layout` slot.
fn destroyShaderLayout(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout) callconv(.c) void {
    if (self == null) return;
    const sl = pointed(ShaderLayout, layout) orelse return;
    releaseShaderLayout(stateOf(self).device, sl);
}

/// The binder's `pipeline_layouts` slot: each group's layout at the index the shader gives it. A
/// shader whose groups leave an index empty below the highest is refused.
fn pipelineLayouts(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout, out_layouts: [*c]c.ke_gpu_bind_group_layout, capacity: u32, out_count: [*c]u32) callconv(.c) c.ke_result {
    const sl = pointed(ShaderLayout, layout) orelse return R.code(error.InvalidArgument);
    if (self == null or out_layouts == null or out_count == null) return R.code(error.InvalidArgument);
    out_count.* = 0;
    const count: u32 = @intCast(sl.groups.items.len);
    if (count > capacity) {
        log.warn("pipeline_layouts: the shader needs {d} layouts, more than the capacity of {d}", .{ count, capacity });
        return R.code(error.InvalidArgument);
    }
    for (0..count) |i| out_layouts[i] = c.KE_GPU_INVALID_HANDLE;
    for (sl.groups.items) |g| {
        const index = g.group.index orelse 0;
        if (index >= count) {
            log.warn("pipeline_layouts: the shader leaves a group index empty below {d}", .{index});
            return R.code(error.InvalidArgument);
        }
        out_layouts[index] = g.layout;
    }
    out_count.* = count;
    return R.ok;
}

/// The binder's `create_set` slot.
fn createSet(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout, block: [*c]const u8, label: [*c]const u8, bindings: [*c]const c.ke_render_shader_binding, binding_count: u32, out_set: [*c]c.ke_render_resource_set) callconv(.c) c.ke_result {
    const out = out_set orelse return R.code(error.InvalidArgument);
    out.* = c.KE_RENDER_BINDING_INVALID;
    const sl = pointed(ShaderLayout, layout) orelse return R.code(error.InvalidArgument);
    if (self == null or (binding_count != 0 and bindings == null)) return R.code(error.InvalidArgument);
    const given: []const c.ke_render_shader_binding = if (binding_count == 0) &.{} else bindings[0..binding_count];
    const set = resourceSet(stateOf(self), sl, if (block != null) std.mem.span(block) else null, label, given) catch |err| return R.code(err);
    out.* = handleOf(set);
    return R.ok;
}

fn resourceSet(st: *State, sl: *ShaderLayout, block: ?[]const u8, label: [*c]const u8, given: []const c.ke_render_shader_binding) R.Error!*Set {
    const g = findGroup(sl, block) orelse {
        log.warn("create_set: the shader declares no group {s}", .{block orelse "(loose)"});
        return error.NotFound;
    };
    const entries = try reflection.matchBindings(&g.group, given, st.provided.items);
    defer gpa.free(entries);
    const set = try gpa.create(Set);
    errdefer gpa.destroy(set);
    set.* = .{ .index = g.group.index orelse 0, .bind_group = c.KE_GPU_INVALID_HANDLE };
    try R.check(st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .label = label,
        .layout = g.layout,
        .entry_count = @intCast(entries.len),
        .entries = entries.ptr,
    }, &set.bind_group));
    return set;
}

/// The binder's `destroy_set` slot.
fn destroySet(self: [*c]c.ke_render_resource_binder, set: c.ke_render_resource_set) callconv(.c) void {
    if (self == null) return;
    const s = pointed(Set, set) orelse return;
    const dev = stateOf(self).device;
    dev.destroy_bind_group.?(dev, s.bind_group);
    gpa.destroy(s);
}

/// The binder's `bind_render_set` slot.
fn bindRenderSet(self: [*c]c.ke_render_resource_binder, pass: [*c]c.ke_gpu_render_pass, set: c.ke_render_resource_set, offsets: [*c]const u32, offset_count: u32) callconv(.c) void {
    if (self == null or pass == null) return;
    const s = pointed(Set, set) orelse return;
    pass.*.set_bind_group.?(pass, s.index, s.bind_group, offsets, offset_count);
}

/// The binder's `bind_compute_set` slot.
fn bindComputeSet(self: [*c]c.ke_render_resource_binder, pass: [*c]c.ke_gpu_compute_pass, set: c.ke_render_resource_set, offsets: [*c]const u32, offset_count: u32) callconv(.c) void {
    if (self == null or pass == null) return;
    const s = pointed(Set, set) orelse return;
    pass.*.set_bind_group.?(pass, s.index, s.bind_group, offsets, offset_count);
}

/// The binder's `create_material` slot: the material's uniform buffer and one bind group against
/// the material layout, its sampler the one provided as `ke_samp_linear`.
fn createMaterial(self: [*c]c.ke_render_resource_binder, data: [*c]const c.ke_render_material_data, out_material: [*c]c.ke_render_material_binding) callconv(.c) c.ke_result {
    const out = out_material orelse return R.code(error.InvalidArgument);
    out.* = c.KE_RENDER_BINDING_INVALID;
    if (self == null or data == null) return R.code(error.InvalidArgument);
    const m = newMaterial(stateOf(self), data.*) catch |err| return R.code(err);
    out.* = handleOf(m);
    return R.ok;
}

fn newMaterial(st: *State, d: c.ke_render_material_data) R.Error!*Material {
    const uniform = MaterialUniform{
        .base_color = d.base_color,
        .metallic = d.metallic,
        .roughness = d.roughness,
        .alpha_cutoff = d.alpha_cutoff,
        .ior = d.ior,
        .distortion_strength = d.distortion_strength,
    };
    var buffer: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .label = "material.uniform",
        .initial_data = &uniform,
        .size = @sizeOf(MaterialUniform),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = false,
    }, &buffer));
    errdefer st.device.destroy_buffer.?(st.device, buffer);
    var sampler: c.ke_gpu_sampler = c.KE_GPU_INVALID_HANDLE;
    for (st.provided.items) |p| {
        if (std.mem.eql(u8, p.name, material_sampler_source)) sampler = p.binding.sampler;
    }
    const zero = std.mem.zeroes(c.ke_render_shader_binding);
    var bindings = [_]c.ke_render_shader_binding{ zero, zero, zero, zero };
    bindings[0].name = material_block;
    bindings[0].buffer = buffer;
    bindings[0].buffer_size = @sizeOf(MaterialUniform);
    bindings[1].name = "albedo";
    bindings[1].texture_view = d.albedo;
    bindings[2].name = material_sampler;
    bindings[2].sampler = sampler;
    bindings[3].name = "normal_map";
    bindings[3].texture_view = d.normal_map;
    const entries = try reflection.matchBindings(&st.material_group, &bindings, st.provided.items);
    defer gpa.free(entries);
    var bind_group: c.ke_gpu_bind_group = c.KE_GPU_INVALID_HANDLE;
    try R.check(st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .label = "material.bind_group",
        .layout = st.material_layout,
        .entry_count = @intCast(entries.len),
        .entries = entries.ptr,
    }, &bind_group));
    errdefer st.device.destroy_bind_group.?(st.device, bind_group);
    const m = try gpa.create(Material);
    m.* = .{ .uniform = buffer, .bind_group = bind_group };
    return m;
}

/// The binder's `destroy_material` slot.
fn destroyMaterial(self: [*c]c.ke_render_resource_binder, material: c.ke_render_material_binding) callconv(.c) void {
    if (self == null) return;
    const m = pointed(Material, material) orelse return;
    const dev = stateOf(self).device;
    dev.destroy_bind_group.?(dev, m.bind_group);
    dev.destroy_buffer.?(dev, m.uniform);
    gpa.destroy(m);
}

/// The binder's `bind_material` slot: the material's bind group at the shader's material group.
fn bindMaterial(self: [*c]c.ke_render_resource_binder, pass: [*c]c.ke_gpu_render_pass, layout: c.ke_render_shader_layout, material: c.ke_render_material_binding) callconv(.c) void {
    if (self == null or pass == null) return;
    const sl = pointed(ShaderLayout, layout) orelse return;
    const m = pointed(Material, material) orelse return;
    const index = sl.material_index orelse return;
    pass.*.set_bind_group.?(pass, index, m.bind_group, null, 0);
}

/// The `destroy` of the handle the factory returns: the material layout, the provided names and
/// the state. Layouts, sets and materials still alive are the caller's leak.
fn destroyBinder(self: [*c]c.ke_render_resource_binder) callconv(.c) void {
    if (self == null) return;
    const st = stateOf(self);
    if (st.material_layout != c.KE_GPU_INVALID_HANDLE) st.device.destroy_bind_group_layout.?(st.device, st.material_layout);
    st.material_group.deinit();
    for (st.provided.items) |p| gpa.free(p.name);
    st.provided.deinit(gpa);
    gpa.free(st.shader_dir);
    gpa.destroy(st);
}

/// The factory: copies the shader directory, reads the material block from the embedded
/// reflection for the vertex and fragment stages and builds the material layout on the device.
export fn ke_render_resource_binder_grouped_create(params: [*c]const c.ke_render_resource_binder_grouped_params, out_binder: [*c]c.ke_render_resource_binder_handle) callconv(.c) c.ke_result {
    const out = out_binder orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    if (params == null or params.*.device == null or params.*.shader_dir == null) return R.code(error.InvalidArgument);
    const st = newBinder(params.*) catch |err| return R.code(err);
    out.* = .{ .ref = &st.api, .destroy = destroyBinder };
    return R.ok;
}

fn newBinder(params: c.ke_render_resource_binder_grouped_params) R.Error!*State {
    const st = try gpa.create(State);
    const dir = gpa.dupe(u8, std.mem.span(params.shader_dir)) catch |err| {
        gpa.destroy(st);
        return err;
    };
    st.* = .{
        .api = .{
            .handle = st,
            .provide = provide,
            .create_shader_layout = createShaderLayout,
            .destroy_shader_layout = destroyShaderLayout,
            .pipeline_layouts = pipelineLayouts,
            .create_set = createSet,
            .destroy_set = destroySet,
            .bind_render_set = bindRenderSet,
            .bind_compute_set = bindComputeSet,
            .create_material = createMaterial,
            .destroy_material = destroyMaterial,
            .bind_material = bindMaterial,
        },
        .device = params.device,
        .shader_dir = dir,
        .provided = .empty,
        .material_group = reflection.Group.init(gpa),
        .material_layout = c.KE_GPU_INVALID_HANDLE,
    };
    errdefer destroyBinder(&st.api);
    const material_json = @embedFile("material_params.json");
    const read_vs = st.material_group.collect(material_json, material_block, c.KE_GPU_SHADER_STAGE_VERTEX) catch false;
    const read_fs = st.material_group.collect(material_json, material_block, c.KE_GPU_SHADER_STAGE_FRAGMENT) catch false;
    if (!read_vs or !read_fs) {
        log.warn("ke_render_resource_binder_grouped_create: the material parameter block could not be read", .{});
        return error.NotInitialized;
    }
    st.material_layout = try reflection.createLayout(st.device, &st.material_group, "binder.material_layout");
    return st;
}

const testing = std.testing;
const Stubs = @import("stubs").Stubs(c);

test {
    _ = reflection;
}

const lit_vs =
    \\{"parameters":[
    \\ {"name":"ke_frame","binding":{"kind":"descriptorTableSlot","index":0},"type":{"kind":"constantBuffer"}},
    \\ {"name":"object","binding":{"kind":"subElementRegisterSpace","index":2},"type":{"kind":"parameterBlock",
    \\  "elementType":{"kind":"struct","fields":[]},"containerVarLayout":{"binding":{"kind":"descriptorTableSlot","index":0}}}}]}
;

const lit_fs =
    \\{"parameters":[
    \\ {"name":"ke_frame","binding":{"kind":"descriptorTableSlot","index":0},"type":{"kind":"constantBuffer"}},
    \\ {"name":"shadow_map","binding":{"kind":"descriptorTableSlot","index":1},"type":{"kind":"resource","baseShape":"texture2D"}},
    \\ {"name":"mat","binding":{"kind":"subElementRegisterSpace","index":1},"type":{"kind":"parameterBlock",
    \\  "elementType":{"kind":"struct","fields":[]},"containerVarLayout":{"binding":{"kind":"descriptorTableSlot","index":0}}}}]}
;

const gap_fs =
    \\{"parameters":[
    \\ {"name":"ke_frame","binding":{"kind":"descriptorTableSlot","index":0},"type":{"kind":"constantBuffer"}},
    \\ {"name":"object","binding":{"kind":"subElementRegisterSpace","index":2},"type":{"kind":"parameterBlock",
    \\  "elementType":{"kind":"struct","fields":[]},"containerVarLayout":{"binding":{"kind":"descriptorTableSlot","index":0}}}}]}
;

/// What the binder records into: the groups set on a render pass, by index.
const PassProbe = struct {
    pass: c.ke_gpu_render_pass,
    groups: [4]c.ke_gpu_bind_group = .{ 0, 0, 0, 0 },
    offsets: [4]u32 = .{ 0, 0, 0, 0 },

    fn init(self: *PassProbe) void {
        self.* = .{ .pass = std.mem.zeroes(c.ke_gpu_render_pass) };
        self.pass.set_bind_group = setBindGroup;
    }

    fn setBindGroup(pass: [*c]c.ke_gpu_render_pass, index: u32, bg: c.ke_gpu_bind_group, offsets: [*c]const u32, count: u32) callconv(.c) void {
        const self: *PassProbe = @fieldParentPtr("pass", @as(*c.ke_gpu_render_pass, pass));
        self.groups[index] = bg;
        if (count != 0) self.offsets[index] = offsets[0];
    }
};

const Rig = struct {
    dev: Stubs.Device,
    dir: std.testing.TmpDir,
    path: [std.fs.max_path_bytes]u8,

    fn init(self: *Rig) !void {
        self.dev.init();
        self.dir = std.testing.tmpDir(.{});
        errdefer self.dir.cleanup();
        try self.dir.dir.writeFile(testing.io, .{ .sub_path = "lit.vs.json", .data = lit_vs });
        try self.dir.dir.writeFile(testing.io, .{ .sub_path = "lit.fs.json", .data = lit_fs });
        try self.dir.dir.writeFile(testing.io, .{ .sub_path = "gap.fs.json", .data = gap_fs });
        const p = try std.fmt.bufPrint(&self.path, ".zig-cache/tmp/{s}", .{self.dir.sub_path});
        self.path[p.len] = 0;
    }

    fn binder(self: *Rig) !c.ke_render_resource_binder_handle {
        const params = c.ke_render_resource_binder_grouped_params{ .device = self.dev.api(), .shader_dir = @ptrCast(&self.path) };
        var h: c.ke_render_resource_binder_handle = undefined;
        try R.check(ke_render_resource_binder_grouped_create(&params, &h));
        return h;
    }

    fn deinit(self: *Rig) void {
        self.dir.cleanup();
    }
};

fn named(name: [*:0]const u8) c.ke_render_shader_binding {
    var b = std.mem.zeroes(c.ke_render_shader_binding);
    b.name = name;
    return b;
}

test "a shader's groups are placed in a pipeline at the indices the shader gives them, the material group taking the binder's layout" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    var layout: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, &layout));
    defer b.*.destroy_shader_layout.?(b, layout);

    var layouts: [4]c.ke_gpu_bind_group_layout = undefined;
    var count: u32 = 0;
    try R.check(b.*.pipeline_layouts.?(b, layout, &layouts, layouts.len, &count));
    try testing.expectEqual(@as(u32, 3), count);
    try testing.expectEqual(stateOf(b).material_layout, layouts[1]);
    try testing.expect(layouts[0] != c.KE_GPU_INVALID_HANDLE and layouts[2] != c.KE_GPU_INVALID_HANDLE);
}

test "a set binds what the pass names and what the binder was given for the rest, at its group's index" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    var frame = named("ke_frame");
    frame.buffer = 9;
    try R.check(b.*.provide.?(b, &frame));
    const hints = [_]c.ke_render_binding_hint{.{ .name = "object", .flags = c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};
    var layout: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = &hints, .hint_count = hints.len }, &layout));
    defer b.*.destroy_shader_layout.?(b, layout);

    const own = [_]c.ke_render_shader_binding{named("shadow_map")};
    var loose: c.ke_render_resource_set = undefined;
    try R.check(b.*.create_set.?(b, layout, null, "loose", &own, own.len, &loose));
    defer b.*.destroy_set.?(b, loose);
    var object: c.ke_render_resource_set = undefined;
    try R.check(b.*.create_set.?(b, layout, "object", "object", &[_]c.ke_render_shader_binding{named("object")}, 1, &object));
    defer b.*.destroy_set.?(b, object);

    var probe: PassProbe = undefined;
    probe.init();
    b.*.bind_render_set.?(b, &probe.pass, loose, null, 0);
    const offset = [_]u32{256};
    b.*.bind_render_set.?(b, &probe.pass, object, &offset, 1);
    try testing.expectEqual(pointed(Set, loose).?.bind_group, probe.groups[0]);
    try testing.expectEqual(pointed(Set, object).?.bind_group, probe.groups[2]);
    try testing.expectEqual(@as(u32, 256), probe.offsets[2]);

    var absent: c.ke_render_resource_set = undefined;
    try testing.expectError(error.NotFound, R.check(b.*.create_set.?(b, layout, "absent", null, null, 0, &absent)));
    try testing.expectEqual(@as(u64, c.KE_RENDER_BINDING_INVALID), absent);
}

test "a material is bound at the material group of the shader drawing it, and not at all by a shader without one" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    var data = std.mem.zeroes(c.ke_render_material_data);
    data.albedo = 3;
    data.normal_map = 4;
    var material: c.ke_render_material_binding = undefined;
    try R.check(b.*.create_material.?(b, &data, &material));
    defer b.*.destroy_material.?(b, material);

    var lit: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, &lit));
    defer b.*.destroy_shader_layout.?(b, lit);
    var probe: PassProbe = undefined;
    probe.init();
    b.*.bind_material.?(b, &probe.pass, lit, material);
    try testing.expectEqual(pointed(Material, material).?.bind_group, probe.groups[1]);

    var plain: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX, .hints = null, .hint_count = 0 }, &plain));
    defer b.*.destroy_shader_layout.?(b, plain);
    var untouched: PassProbe = undefined;
    untouched.init();
    b.*.bind_material.?(b, &untouched.pass, plain, material);
    try testing.expectEqual([_]c.ke_gpu_bind_group{ 0, 0, 0, 0 }, untouched.groups);
}

test "a shader that leaves a group index empty below its highest is refused a pipeline layout" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    var layout: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "gap", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, &layout));
    defer b.*.destroy_shader_layout.?(b, layout);
    var layouts: [4]c.ke_gpu_bind_group_layout = undefined;
    var count: u32 = 0;
    try testing.expectError(error.InvalidArgument, R.check(b.*.pipeline_layouts.?(b, layout, &layouts, layouts.len, &count)));
}

test "a hint naming no parameter of the shader is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    const hints = [_]c.ke_render_binding_hint{.{ .name = "nothing", .flags = c.KE_RENDER_BINDING_HINT_DEPTH }};
    var layout: c.ke_render_shader_layout = undefined;
    try testing.expectError(error.InvalidArgument, R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = &hints, .hint_count = hints.len }, &layout)));
    try testing.expectEqual(@as(u64, c.KE_RENDER_BINDING_INVALID), layout);
}

test "creating a binder and everything it hands out, then destroying them, leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    const b = h.ref;
    var frame = named("ke_frame");
    try R.check(b.*.provide.?(b, &frame));
    var layout: c.ke_render_shader_layout = undefined;
    try R.check(b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, &layout));
    var set: c.ke_render_resource_set = undefined;
    try R.check(b.*.create_set.?(b, layout, null, null, &[_]c.ke_render_shader_binding{named("shadow_map")}, 1, &set));
    var data = std.mem.zeroes(c.ke_render_material_data);
    var material: c.ke_render_material_binding = undefined;
    try R.check(b.*.create_material.?(b, &data, &material));
    b.*.destroy_material.?(b, material);
    b.*.destroy_set.?(b, set);
    b.*.destroy_shader_layout.?(b, layout);
    h.destroy.?(b);
    try testing.expectEqual(@as(i64, 0), rig.dev.live);
    try heap.expectNoLeaks();
}
