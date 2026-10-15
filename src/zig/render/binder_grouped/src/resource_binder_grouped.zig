//! The grouped resource binder: every group a shader declares is one bind group, and every material
//! is one bind group of its own, behind the one factory the plugin exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };

const c = @import("cimport.zig").c;
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

fn fail(out_error: [*c][*c]c.ke_error, kind: *const c.ke_error_type, message: [*c]const u8, src: std.builtin.SourceLocation) void {
    c.ke_error_set(out_error, kind, message, src.file, @intCast(src.line), null);
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
fn provide(self: [*c]c.ke_render_resource_binder, binding: [*c]const c.ke_render_shader_binding, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    if (self == null or binding == null or binding.*.name == null) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "provide: a named binding is required", @src());
        return false;
    }
    const st = stateOf(self);
    const name = std.mem.span(binding.*.name);
    for (st.provided.items) |*p| {
        if (std.mem.eql(u8, p.name, name)) {
            p.binding = binding.*;
            p.binding.name = p.name.ptr;
            return true;
        }
    }
    const owned = gpa.dupeZ(u8, name) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "provide: the name cannot be kept", @src());
        return false;
    };
    var kept = binding.*;
    kept.name = owned.ptr;
    st.provided.append(gpa, .{ .name = owned, .binding = kept }) catch {
        gpa.free(owned);
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "provide: the binding cannot be kept", @src());
        return false;
    };
    return true;
}

/// Adds to `sl` a group for the loose parameters and for each block the reflection `json` of
/// `stage` declares, then reads every group's bindings from it.
fn collectStage(sl: *ShaderLayout, json: []const u8, stage: u32, out_error: [*c][*c]c.ke_error) bool {
    var names_arena = std.heap.ArenaAllocator.init(gpa);
    defer names_arena.deinit();
    const names = reflection.blockNames(names_arena.allocator(), json) catch |err| return readFailed(err, out_error);
    if (findGroup(sl, null) == null and !addGroup(sl, null, out_error)) return false;
    for (names) |name| {
        if (findGroup(sl, name) == null and !addGroup(sl, name, out_error)) return false;
    }
    for (sl.groups.items) |*g| {
        _ = g.group.collect(json, g.block, stage) catch |err| return readFailed(err, out_error);
    }
    return true;
}

fn addGroup(sl: *ShaderLayout, block: ?[]const u8, out_error: [*c][*c]c.ke_error) bool {
    const owned: ?[]u8 = if (block) |b| (gpa.dupe(u8, b) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_shader_layout: out of memory", @src());
        return false;
    }) else null;
    sl.groups.append(gpa, .{ .block = owned, .group = reflection.Group.init(gpa), .layout = c.KE_GPU_INVALID_HANDLE, .owned = false }) catch {
        if (owned) |o| gpa.free(o);
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_shader_layout: out of memory", @src());
        return false;
    };
    return true;
}

fn readFailed(err: reflection.ReadError, out_error: [*c][*c]c.ke_error) bool {
    fail(out_error, if (err == error.OutOfMemory) &c.KE_ERROR_OUT_OF_MEMORY else &c.KE_ERROR_INVALID_ARGUMENT, switch (err) {
        error.OutOfMemory => "create_shader_layout: out of memory reading the reflection",
        error.Malformed => "create_shader_layout: the reflection declares a parameter it cannot read",
        error.LooseUniform => "create_shader_layout: the shader declares a loose uniform outside any buffer or block",
        error.MismatchedGroup => "create_shader_layout: the stages place a parameter at different bindings",
    }, @src());
    return false;
}

/// Drops the loose group when the shader declares no loose parameter, applies the hints, and
/// builds each group's layout, the material block taking the binder's.
fn finishLayout(st: *State, sl: *ShaderLayout, params: *const c.ke_render_shader_layout_params, out_error: [*c][*c]c.ke_error) bool {
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
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_shader_layout: a hint names no parameter of the shader", @src());
            return false;
        }
    }
    for (sl.groups.items, 0..) |*g, gi| {
        const index = g.group.index orelse 0;
        for (sl.groups.items[0..gi]) |earlier| {
            if ((earlier.group.index orelse 0) == index) {
                fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_shader_layout: two groups of the shader share an index", @src());
                return false;
            }
        }
        if (g.block != null and std.mem.eql(u8, g.block.?, material_block)) {
            g.layout = st.material_layout;
            sl.material_index = index;
            continue;
        }
        g.layout = reflection.createLayout(st.device, &g.group, params.shader, out_error);
        if (g.layout == c.KE_GPU_INVALID_HANDLE) return false;
        g.owned = true;
    }
    return true;
}

/// The binder's `create_shader_layout` slot: reads "<shader dir>/<shader>.<vs|fs|cs>.json" for
/// each stage of the params.
fn createShaderLayout(self: [*c]c.ke_render_resource_binder, params: [*c]const c.ke_render_shader_layout_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_shader_layout {
    if (self == null or params == null or params.*.shader == null or params.*.stages == 0) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_shader_layout: a shader name and at least one stage are required", @src());
        return c.KE_RENDER_BINDING_INVALID;
    }
    const st = stateOf(self);
    const sl = gpa.create(ShaderLayout) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_shader_layout: out of memory", @src());
        return c.KE_RENDER_BINDING_INVALID;
    };
    sl.* = .{ .groups = .empty, .material_index = null };
    for (stage_suffixes) |s| {
        if (params.*.stages & s.bit == 0) continue;
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrintZ(&path_buf, "{s}/{s}.{s}.json", .{ st.shader_dir, std.mem.span(params.*.shader), s.suffix }) catch {
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_shader_layout: resolved reflection path too long", @src());
            releaseShaderLayout(st.device, sl);
            return c.KE_RENDER_BINDING_INVALID;
        };
        const json = shader_files.read(gpa, path, out_error) orelse {
            releaseShaderLayout(st.device, sl);
            return c.KE_RENDER_BINDING_INVALID;
        };
        defer gpa.free(json);
        if (!collectStage(sl, json, s.bit, out_error)) {
            releaseShaderLayout(st.device, sl);
            return c.KE_RENDER_BINDING_INVALID;
        }
    }
    if (!finishLayout(st, sl, params, out_error)) {
        releaseShaderLayout(st.device, sl);
        return c.KE_RENDER_BINDING_INVALID;
    }
    return handleOf(sl);
}

/// The binder's `destroy_shader_layout` slot.
fn destroyShaderLayout(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout) callconv(.c) void {
    if (self == null) return;
    const sl = pointed(ShaderLayout, layout) orelse return;
    releaseShaderLayout(stateOf(self).device, sl);
}

/// The binder's `pipeline_layouts` slot: each group's layout at the index the shader gives it. A
/// shader whose groups leave an index empty below the highest is refused.
fn pipelineLayouts(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout, out_layouts: [*c]c.ke_gpu_bind_group_layout, capacity: u32, out_count: [*c]u32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const sl = pointed(ShaderLayout, layout) orelse {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "pipeline_layouts: unknown layout", @src());
        return false;
    };
    if (self == null or out_layouts == null or out_count == null) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "pipeline_layouts: null argument", @src());
        return false;
    }
    const count: u32 = @intCast(sl.groups.items.len);
    if (count > capacity) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "pipeline_layouts: the shader needs more layouts than the capacity", @src());
        return false;
    }
    for (0..count) |i| out_layouts[i] = c.KE_GPU_INVALID_HANDLE;
    for (sl.groups.items) |g| {
        const index = g.group.index orelse 0;
        if (index >= count) {
            fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "pipeline_layouts: the shader leaves a group index empty", @src());
            return false;
        }
        out_layouts[index] = g.layout;
    }
    out_count.* = count;
    return true;
}

/// The binder's `create_set` slot.
fn createSet(self: [*c]c.ke_render_resource_binder, layout: c.ke_render_shader_layout, block: [*c]const u8, label: [*c]const u8, bindings: [*c]const c.ke_render_shader_binding, binding_count: u32, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_resource_set {
    const sl = pointed(ShaderLayout, layout) orelse {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_set: unknown layout", @src());
        return c.KE_RENDER_BINDING_INVALID;
    };
    if (self == null or (binding_count != 0 and bindings == null)) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_set: null argument", @src());
        return c.KE_RENDER_BINDING_INVALID;
    }
    const st = stateOf(self);
    const block_name: ?[]const u8 = if (block != null) std.mem.span(block) else null;
    const g = findGroup(sl, block_name) orelse {
        fail(out_error, &c.KE_ERROR_NOT_FOUND, "create_set: the shader declares no such group", @src());
        return c.KE_RENDER_BINDING_INVALID;
    };
    const given: []const c.ke_render_shader_binding = if (binding_count == 0) &.{} else bindings[0..binding_count];
    const entries = reflection.matchBindings(&g.group, given, st.provided.items, out_error) orelse return c.KE_RENDER_BINDING_INVALID;
    defer gpa.free(entries);
    const set = gpa.create(Set) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_set: out of memory", @src());
        return c.KE_RENDER_BINDING_INVALID;
    };
    set.* = .{
        .index = g.group.index orelse 0,
        .bind_group = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
            .label = label,
            .layout = g.layout,
            .entry_count = @intCast(entries.len),
            .entries = entries.ptr,
        }, out_error),
    };
    if (set.bind_group == c.KE_GPU_INVALID_HANDLE) {
        gpa.destroy(set);
        return c.KE_RENDER_BINDING_INVALID;
    }
    return handleOf(set);
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
fn createMaterial(self: [*c]c.ke_render_resource_binder, data: [*c]const c.ke_render_material_data, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_material_binding {
    if (self == null or data == null) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "create_material: null argument", @src());
        return c.KE_RENDER_BINDING_INVALID;
    }
    const st = stateOf(self);
    const d = data.*;
    const uniform = MaterialUniform{
        .base_color = d.base_color,
        .metallic = d.metallic,
        .roughness = d.roughness,
        .alpha_cutoff = d.alpha_cutoff,
        .ior = d.ior,
        .distortion_strength = d.distortion_strength,
    };
    const buffer = st.device.create_buffer.?(st.device, &c.ke_gpu_buffer_params{
        .label = "material.uniform",
        .initial_data = &uniform,
        .size = @sizeOf(MaterialUniform),
        .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST,
        .mapped_at_creation = 0,
    }, out_error);
    if (buffer == c.KE_GPU_INVALID_HANDLE) return c.KE_RENDER_BINDING_INVALID;
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
    const entries = reflection.matchBindings(&st.material_group, &bindings, st.provided.items, out_error) orelse {
        st.device.destroy_buffer.?(st.device, buffer);
        return c.KE_RENDER_BINDING_INVALID;
    };
    defer gpa.free(entries);
    const bind_group = st.device.create_bind_group.?(st.device, &c.ke_gpu_bind_group_params{
        .label = "material.bind_group",
        .layout = st.material_layout,
        .entry_count = @intCast(entries.len),
        .entries = entries.ptr,
    }, out_error);
    if (bind_group == c.KE_GPU_INVALID_HANDLE) {
        st.device.destroy_buffer.?(st.device, buffer);
        return c.KE_RENDER_BINDING_INVALID;
    }
    const m = gpa.create(Material) catch {
        st.device.destroy_bind_group.?(st.device, bind_group);
        st.device.destroy_buffer.?(st.device, buffer);
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "create_material: out of memory", @src());
        return c.KE_RENDER_BINDING_INVALID;
    };
    m.* = .{ .uniform = buffer, .bind_group = bind_group };
    return handleOf(m);
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
export fn ke_render_resource_binder_grouped_create(params: [*c]const c.ke_render_resource_binder_grouped_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_resource_binder_handle {
    const none = c.ke_render_resource_binder_handle{ .ref = null, .destroy = null };
    if (params == null or params.*.device == null or params.*.shader_dir == null) {
        fail(out_error, &c.KE_ERROR_INVALID_ARGUMENT, "ke_render_resource_binder_grouped_create: a device and a shader directory are required", @src());
        return none;
    }
    const st = gpa.create(State) catch {
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ke_render_resource_binder_grouped_create: out of memory", @src());
        return none;
    };
    const dir = gpa.dupe(u8, std.mem.span(params.*.shader_dir)) catch {
        gpa.destroy(st);
        fail(out_error, &c.KE_ERROR_OUT_OF_MEMORY, "ke_render_resource_binder_grouped_create: out of memory", @src());
        return none;
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
        .device = params.*.device,
        .shader_dir = dir,
        .provided = .empty,
        .material_group = reflection.Group.init(gpa),
        .material_layout = c.KE_GPU_INVALID_HANDLE,
    };
    const material_json = @embedFile("material_params.json");
    const read_vs = st.material_group.collect(material_json, material_block, c.KE_GPU_SHADER_STAGE_VERTEX) catch false;
    const read_fs = st.material_group.collect(material_json, material_block, c.KE_GPU_SHADER_STAGE_FRAGMENT) catch false;
    if (!read_vs or !read_fs) {
        fail(out_error, &c.KE_ERROR_NOT_INITIALIZED, "ke_render_resource_binder_grouped_create: the material parameter block could not be read", @src());
        destroyBinder(&st.api);
        return none;
    }
    st.material_layout = reflection.createLayout(st.device, &st.material_group, "binder.material_layout", out_error);
    if (st.material_layout == c.KE_GPU_INVALID_HANDLE) {
        destroyBinder(&st.api);
        return none;
    }
    return .{ .ref = &st.api, .destroy = destroyBinder };
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
        const h = ke_render_resource_binder_grouped_create(&params, null);
        if (h.ref == null) return error.TestUnexpectedResult;
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

    const layout = b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, null);
    try testing.expect(layout != c.KE_RENDER_BINDING_INVALID);
    defer b.*.destroy_shader_layout.?(b, layout);

    var layouts: [4]c.ke_gpu_bind_group_layout = undefined;
    var count: u32 = 0;
    try testing.expect(b.*.pipeline_layouts.?(b, layout, &layouts, layouts.len, &count, null));
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
    try testing.expect(b.*.provide.?(b, &frame, null));
    const hints = [_]c.ke_render_binding_hint{.{ .name = "object", .flags = c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};
    const layout = b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = &hints, .hint_count = hints.len }, null);
    defer b.*.destroy_shader_layout.?(b, layout);

    const own = [_]c.ke_render_shader_binding{named("shadow_map")};
    const loose = b.*.create_set.?(b, layout, null, "loose", &own, own.len, null);
    try testing.expect(loose != c.KE_RENDER_BINDING_INVALID);
    defer b.*.destroy_set.?(b, loose);
    const object = b.*.create_set.?(b, layout, "object", "object", &[_]c.ke_render_shader_binding{named("object")}, 1, null);
    defer b.*.destroy_set.?(b, object);

    var probe: PassProbe = undefined;
    probe.init();
    b.*.bind_render_set.?(b, &probe.pass, loose, null, 0);
    const offset = [_]u32{256};
    b.*.bind_render_set.?(b, &probe.pass, object, &offset, 1);
    try testing.expectEqual(pointed(Set, loose).?.bind_group, probe.groups[0]);
    try testing.expectEqual(pointed(Set, object).?.bind_group, probe.groups[2]);
    try testing.expectEqual(@as(u32, 256), probe.offsets[2]);

    var err: [*c]c.ke_error = null;
    try testing.expectEqual(@as(u64, c.KE_RENDER_BINDING_INVALID), b.*.create_set.?(b, layout, "absent", null, null, 0, &err));
    try testing.expect(err != null);
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
    const material = b.*.create_material.?(b, &data, null);
    try testing.expect(material != c.KE_RENDER_BINDING_INVALID);
    defer b.*.destroy_material.?(b, material);

    const lit = b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, null);
    defer b.*.destroy_shader_layout.?(b, lit);
    var probe: PassProbe = undefined;
    probe.init();
    b.*.bind_material.?(b, &probe.pass, lit, material);
    try testing.expectEqual(pointed(Material, material).?.bind_group, probe.groups[1]);

    const plain = b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX, .hints = null, .hint_count = 0 }, null);
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

    const layout = b.*.create_shader_layout.?(b, &.{ .shader = "gap", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, null);
    defer b.*.destroy_shader_layout.?(b, layout);
    var layouts: [4]c.ke_gpu_bind_group_layout = undefined;
    var count: u32 = 0;
    var err: [*c]c.ke_error = null;
    try testing.expect(!b.*.pipeline_layouts.?(b, layout, &layouts, layouts.len, &count, &err));
    try testing.expect(err != null);
}

test "a hint naming no parameter of the shader is refused" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    defer h.destroy.?(h.ref);
    const b = h.ref;

    const hints = [_]c.ke_render_binding_hint{.{ .name = "nothing", .flags = c.KE_RENDER_BINDING_HINT_DEPTH }};
    var err: [*c]c.ke_error = null;
    try testing.expectEqual(@as(u64, c.KE_RENDER_BINDING_INVALID), b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = &hints, .hint_count = hints.len }, &err));
    try testing.expect(err != null);
}

test "creating a binder and everything it hands out, then destroying them, leaves no block allocated and no GPU resource live" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = try rig.binder();
    const b = h.ref;
    var frame = named("ke_frame");
    _ = b.*.provide.?(b, &frame, null);
    const layout = b.*.create_shader_layout.?(b, &.{ .shader = "lit", .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT, .hints = null, .hint_count = 0 }, null);
    const set = b.*.create_set.?(b, layout, null, null, &[_]c.ke_render_shader_binding{named("shadow_map")}, 1, null);
    var data = std.mem.zeroes(c.ke_render_material_data);
    const material = b.*.create_material.?(b, &data, null);
    b.*.destroy_material.?(b, material);
    b.*.destroy_set.?(b, set);
    b.*.destroy_shader_layout.?(b, layout);
    h.destroy.?(b);
    try testing.expectEqual(@as(i64, 0), rig.dev.live);
    try heap.expectNoLeaks();
}
