//! The `ke_render_graph` contract at its first step, over one `ke_gpu_device` on one thread: orders the passes by
//! their dependencies and injection points, drops the passes nothing needs, makes the frame's resources when it
//! executes and frees them when the next frame begins, records the passes in order into one encoder and submits it.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_graph_simple").logFn };

const abi_completion = @import("abi_completion");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const heap = @import("heap");

const R = @import("result").Result(.{});
const log = std.log.scoped(.render_graph);

const g = abi_render_graph.c;
const gpu = abi_render_gpu.c;
const Result = abi_result.c.ke_result;
const Completion = abi_completion.c.ke_completion;
const ResourceId = g.ke_render_graph_resource;
const gpa = heap.gpa;
const invalid: u64 = gpu.KE_GPU_INVALID_HANDLE;

/// A resource of the frame: what it was declared as, the GPU objects behind it once the frame executes, and
/// whether the graph made them (`owned`), so the next frame frees them, or they came from outside or an export.
const Resource = struct {
    kind: g.ke_render_graph_resource_kind,
    name: [:0]u8,
    texture_desc: g.ke_render_graph_texture_desc = std.mem.zeroes(g.ke_render_graph_texture_desc),
    buffer_size: u64 = 0,
    imported: bool = false,
    exported: ?g.ke_render_graph_export = null,
    texture: u64 = invalid,
    view: u64 = invalid,
    buffer: u64 = invalid,
    width: u32 = 0,
    height: u32 = 0,
    texture_usage: gpu.ke_gpu_texture_usage = 0,
    buffer_usage: gpu.ke_gpu_buffer_usage = 0,
    owned: bool = false,
};

/// A pass of the frame, with a copy of its uses; `alive` once compile kept it.
const Pass = struct {
    desc: g.ke_render_graph_pass_desc,
    name: [:0]u8,
    uses: []g.ke_render_graph_use,
    alive: bool = false,
    needed: bool = false,
    root: bool = false,
    preds: std.ArrayList(u32) = .empty,
};

/// A resource kept past its frame: its GPU objects and its shape.
const Export = struct {
    kind: g.ke_render_graph_resource_kind,
    texture: u64,
    view: u64,
    buffer: u64,
    format: gpu.ke_gpu_texture_format,
    width: u32,
    height: u32,
    size: u64,
};

/// The completion of an execution: finished when execute returns, carrying the first failure of a record.
const Done = struct {
    api: Completion,
    result: Result,
};

/// The state behind the handle, whose `api.handle` points back at it. `resources` and `passes` are the
/// frame being declared, a resource's id its index plus one; `order` is what compile kept, in order;
/// `views` are the views execute made for a use and the next frame frees; `exports` outlive frames.
const State = struct {
    api: g.ke_render_graph,
    ctx: g.ke_render_graph_ctx = undefined,
    device: *gpu.ke_gpu_device,
    width: u32 = 0,
    height: u32 = 0,
    resources: std.ArrayList(Resource) = .empty,
    passes: std.ArrayList(Pass) = .empty,
    order: std.ArrayList(u32) = .empty,
    views: std.ArrayList(u64) = .empty,
    exports: std.AutoHashMapUnmanaged(g.ke_render_graph_export, Export) = .empty,
    next_export: g.ke_render_graph_export = 1,
    compiled: bool = false,
    current: ?*Pass = null,
    encoder: ?*gpu.ke_gpu_command_encoder = null,
    render_pass: ?*gpu.ke_gpu_render_pass = null,
    compute_pass: ?*gpu.ke_gpu_compute_pass = null,
};

fn stateOf(self: ?*g.ke_render_graph) ?*State {
    return @ptrCast(@alignCast((self orelse return null).handle orelse return null));
}

fn resourceOf(s: *State, id: ResourceId) ?*Resource {
    if (id == 0 or id > s.resources.items.len) return null;
    return &s.resources.items[id - 1];
}

fn freeFrame(s: *State) void {
    for (s.views.items) |v| s.device.destroy_texture_view.?(s.device, v);
    s.views.clearRetainingCapacity();
    for (s.resources.items) |*r| {
        if (r.owned and r.exported == null) {
            if (r.view != invalid) s.device.destroy_texture_view.?(s.device, r.view);
            if (r.texture != invalid) s.device.destroy_texture.?(s.device, r.texture);
            if (r.buffer != invalid) s.device.destroy_buffer.?(s.device, r.buffer);
        }
        gpa.free(r.name);
    }
    s.resources.clearRetainingCapacity();
    for (s.passes.items) |*p| {
        gpa.free(p.name);
        gpa.free(p.uses);
        p.preds.deinit(gpa);
    }
    s.passes.clearRetainingCapacity();
    s.order.clearRetainingCapacity();
    s.compiled = false;
}

/// Slot `begin_frame`: frees what the previous frame made, its exports kept.
fn beginFrame(self: ?*g.ke_render_graph, width: u32, height: u32) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (width == 0 or height == 0) return R.code(error.InvalidArgument);
    freeFrame(s);
    s.width = width;
    s.height = height;
    return R.ok;
}

fn add(s: *State, resource: Resource, out: *ResourceId) R.Error!void {
    s.resources.append(gpa, resource) catch return error.OutOfMemory;
    out.* = @intCast(s.resources.items.len);
}

fn dupName(name: ?[*:0]const u8) R.Error![:0]u8 {
    return gpa.dupeZ(u8, if (name) |n| std.mem.span(n) else "") catch error.OutOfMemory;
}

/// Slot `create_texture`.
fn createTexture(self: ?*g.ke_render_graph, desc_in: ?*const g.ke_render_graph_texture_desc, out_resource: ?*ResourceId) callconv(.c) Result {
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const d = desc_in orelse return R.code(error.InvalidArgument);
    if (d.mip_levels == 0 or d.array_layers == 0 or d.samples == 0 or d.format == gpu.KE_GPU_TEXTURE_FORMAT_INVALID) return R.code(error.InvalidArgument);
    switch (d.size_class) {
        g.KE_RENDER_GRAPH_SIZE_ABSOLUTE => if (d.width == 0 or d.height == 0) return R.code(error.InvalidArgument),
        g.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE => if (d.scale_x <= 0 or d.scale_y <= 0) return R.code(error.InvalidArgument),
        g.KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE => {
            const base = resourceOf(s, d.relative_to) orelse return R.code(error.InvalidArgument);
            if (base.kind != g.KE_RENDER_GRAPH_RESOURCE_TEXTURE or d.scale_x <= 0 or d.scale_y <= 0) return R.code(error.InvalidArgument);
        },
        else => return R.code(error.InvalidArgument),
    }
    if (d.generate_mips) {
        log.warn("render graph: generating mips is not offered by this graph", .{});
        return R.code(error.NotSupported);
    }
    const name = dupName(d.name) catch |err| return R.code(err);
    add(s, .{ .kind = g.KE_RENDER_GRAPH_RESOURCE_TEXTURE, .name = name, .texture_desc = d.*, .owned = true }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `create_buffer`.
fn createBuffer(self: ?*g.ke_render_graph, desc_in: ?*const g.ke_render_graph_buffer_desc, out_resource: ?*ResourceId) callconv(.c) Result {
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const d = desc_in orelse return R.code(error.InvalidArgument);
    if (d.size == 0) return R.code(error.InvalidArgument);
    const name = dupName(d.name) catch |err| return R.code(err);
    add(s, .{ .kind = g.KE_RENDER_GRAPH_RESOURCE_BUFFER, .name = name, .buffer_size = d.size, .owned = true }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `create_token`.
fn createToken(self: ?*g.ke_render_graph, name_in: ?[*:0]const u8, out_resource: ?*ResourceId) callconv(.c) Result {
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const name = dupName(name_in) catch |err| return R.code(err);
    add(s, .{ .kind = g.KE_RENDER_GRAPH_RESOURCE_TOKEN, .name = name }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `import_texture`.
fn importTexture(self: ?*g.ke_render_graph, texture: u64, view: u64, format: gpu.ke_gpu_texture_format, width: u32, height: u32, final_usage: g.ke_render_graph_usage, out_resource: ?*ResourceId) callconv(.c) Result {
    _ = final_usage;
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (view == invalid or width == 0 or height == 0) return R.code(error.InvalidArgument);
    const name = dupName("imported") catch |err| return R.code(err);
    var desc = std.mem.zeroes(g.ke_render_graph_texture_desc);
    desc.format = format;
    desc.width = width;
    desc.height = height;
    add(s, .{ .kind = g.KE_RENDER_GRAPH_RESOURCE_TEXTURE, .name = name, .texture_desc = desc, .imported = true, .texture = texture, .view = view, .width = width, .height = height }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `import_buffer`.
fn importBuffer(self: ?*g.ke_render_graph, buffer: u64, size: u64, out_resource: ?*ResourceId) callconv(.c) Result {
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (buffer == invalid or size == 0) return R.code(error.InvalidArgument);
    const name = dupName("imported") catch |err| return R.code(err);
    add(s, .{ .kind = g.KE_RENDER_GRAPH_RESOURCE_BUFFER, .name = name, .buffer_size = size, .imported = true, .buffer = buffer }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

/// Slot `export_resource`: the objects become the export's once the frame executed.
fn exportResource(self: ?*g.ke_render_graph, id: ResourceId, out_export: ?*g.ke_render_graph_export) callconv(.c) Result {
    const out = out_export orelse return R.code(error.InvalidArgument);
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const r = resourceOf(s, id) orelse return R.code(error.InvalidArgument);
    if (r.kind == g.KE_RENDER_GRAPH_RESOURCE_TOKEN) return R.code(error.InvalidArgument);
    if (r.exported) |e| {
        out.* = e;
        return R.ok;
    }
    const e = s.next_export;
    s.exports.put(gpa, e, .{ .kind = r.kind, .texture = invalid, .view = invalid, .buffer = invalid, .format = r.texture_desc.format, .width = 0, .height = 0, .size = r.buffer_size }) catch return R.code(error.OutOfMemory);
    s.next_export += 1;
    r.exported = e;
    out.* = e;
    return R.ok;
}

/// Slot `import_export`.
fn importExport(self: ?*g.ke_render_graph, exported: g.ke_render_graph_export, out_resource: ?*ResourceId) callconv(.c) Result {
    const out = out_resource orelse return R.code(error.InvalidArgument);
    out.* = g.KE_RENDER_GRAPH_RESOURCE_INVALID;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const e = s.exports.get(exported) orelse return R.code(error.NotFound);
    if (e.texture == invalid and e.buffer == invalid) return R.code(error.NotFound);
    const name = dupName("exported") catch |err| return R.code(err);
    var desc = std.mem.zeroes(g.ke_render_graph_texture_desc);
    desc.format = e.format;
    desc.width = e.width;
    desc.height = e.height;
    add(s, .{ .kind = e.kind, .name = name, .texture_desc = desc, .buffer_size = e.size, .imported = true, .texture = e.texture, .view = e.view, .buffer = e.buffer, .width = e.width, .height = e.height }, out) catch |err| {
        gpa.free(name);
        return R.code(err);
    };
    return R.ok;
}

fn freeExport(s: *State, e: Export) void {
    if (e.view != invalid) s.device.destroy_texture_view.?(s.device, e.view);
    if (e.texture != invalid) s.device.destroy_texture.?(s.device, e.texture);
    if (e.buffer != invalid) s.device.destroy_buffer.?(s.device, e.buffer);
}

/// Slot `release_export`: the device defers the destruction past the work that still uses it.
fn releaseExport(self: ?*g.ke_render_graph, exported: g.ke_render_graph_export) callconv(.c) void {
    const s = stateOf(self) orelse return;
    const e = s.exports.fetchRemove(exported) orelse return;
    freeExport(s, e.value);
}

fn writes(usage: g.ke_render_graph_usage) bool {
    return switch (usage) {
        g.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT, g.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE, g.KE_RENDER_GRAPH_USAGE_COPY_DST, g.KE_RENDER_GRAPH_USAGE_TOKEN_WRITE, g.KE_RENDER_GRAPH_USAGE_AS_BUILD => true,
        else => false,
    };
}

fn offered(usage: g.ke_render_graph_usage) bool {
    return switch (usage) {
        g.KE_RENDER_GRAPH_USAGE_READBACK, g.KE_RENDER_GRAPH_USAGE_RESOLVE, g.KE_RENDER_GRAPH_USAGE_AS_BUILD, g.KE_RENDER_GRAPH_USAGE_AS_READ => false,
        else => true,
    };
}

fn fits(kind: g.ke_render_graph_resource_kind, usage: g.ke_render_graph_usage) bool {
    return switch (usage) {
        g.KE_RENDER_GRAPH_USAGE_TOKEN_READ, g.KE_RENDER_GRAPH_USAGE_TOKEN_WRITE => kind == g.KE_RENDER_GRAPH_RESOURCE_TOKEN,
        g.KE_RENDER_GRAPH_USAGE_SAMPLED, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT, g.KE_RENDER_GRAPH_USAGE_DEPTH_READ, g.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE, g.KE_RENDER_GRAPH_USAGE_INPUT_ATTACHMENT, g.KE_RENDER_GRAPH_USAGE_PRESENT => kind == g.KE_RENDER_GRAPH_RESOURCE_TEXTURE,
        g.KE_RENDER_GRAPH_USAGE_VERTEX, g.KE_RENDER_GRAPH_USAGE_INDEX, g.KE_RENDER_GRAPH_USAGE_INDIRECT, g.KE_RENDER_GRAPH_USAGE_UNIFORM => kind == g.KE_RENDER_GRAPH_RESOURCE_BUFFER,
        else => kind == g.KE_RENDER_GRAPH_RESOURCE_TEXTURE or kind == g.KE_RENDER_GRAPH_RESOURCE_BUFFER,
    };
}

/// Slot `add_pass`.
fn addPass(self: ?*g.ke_render_graph, desc_in: ?*const g.ke_render_graph_pass_desc, out_pass: ?*g.ke_render_graph_pass) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    const d = desc_in orelse return R.code(error.InvalidArgument);
    const out = out_pass orelse return R.code(error.InvalidArgument);
    if (d.record == null) return R.code(error.InvalidArgument);
    const uses: []const g.ke_render_graph_use = if (d.use_count == 0) &.{} else (d.uses orelse return R.code(error.InvalidArgument))[0..d.use_count];
    for (uses) |u| {
        const r = resourceOf(s, u.resource) orelse return R.code(error.InvalidArgument);
        if (r.kind == g.KE_RENDER_GRAPH_RESOURCE_ACCELERATION_STRUCTURE or !offered(u.usage)) {
            log.warn("render graph: pass {s} uses what this graph does not offer", .{if (d.name) |n| std.mem.span(n) else ""});
            return R.code(error.NotSupported);
        }
        if (!fits(r.kind, u.usage)) return R.code(error.InvalidArgument);
    }
    const name = dupName(d.name) catch |err| return R.code(err);
    const copy = gpa.dupe(g.ke_render_graph_use, uses) catch {
        gpa.free(name);
        return R.code(error.OutOfMemory);
    };
    s.passes.append(gpa, .{ .desc = d.*, .name = name, .uses = copy }) catch {
        gpa.free(name);
        gpa.free(copy);
        return R.code(error.OutOfMemory);
    };
    out.* = @intCast(s.passes.items.len);
    s.compiled = false;
    return R.ok;
}

fn link(s: *State, from: u32, to: u32) R.Error!void {
    const preds = &s.passes.items[to].preds;
    if (std.mem.indexOfScalar(u32, preds.items, from) == null) preds.append(gpa, from) catch return error.OutOfMemory;
}

fn markNeeded(s: *State, index: u32) void {
    const p = &s.passes.items[index];
    if (p.needed) return;
    p.needed = true;
    for (p.preds.items) |pred| markNeeded(s, pred);
}

fn sizeOf(s: *State, r: *Resource, depth: u32) [2]u32 {
    if (r.imported or depth > s.resources.items.len) return .{ r.width, r.height };
    const d = r.texture_desc;
    return switch (d.size_class) {
        g.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE => .{ scaled(s.width, d.scale_x), scaled(s.height, d.scale_y) },
        g.KE_RENDER_GRAPH_SIZE_RESOURCE_RELATIVE => blk: {
            const base = sizeOf(s, resourceOf(s, d.relative_to).?, depth + 1);
            break :blk .{ scaled(base[0], d.scale_x), scaled(base[1], d.scale_y) };
        },
        else => .{ d.width, d.height },
    };
}

fn scaled(size: u32, scale: f32) u32 {
    return @max(1, @as(u32, @intFromFloat(@as(f32, @floatFromInt(size)) * scale)));
}

fn textureUsageOf(usage: g.ke_render_graph_usage) gpu.ke_gpu_texture_usage {
    return switch (usage) {
        g.KE_RENDER_GRAPH_USAGE_SAMPLED, g.KE_RENDER_GRAPH_USAGE_INPUT_ATTACHMENT => gpu.KE_GPU_TEXTURE_USAGE_SAMPLED,
        g.KE_RENDER_GRAPH_USAGE_STORAGE_READ, g.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE => gpu.KE_GPU_TEXTURE_USAGE_STORAGE,
        g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT => gpu.KE_GPU_TEXTURE_USAGE_COLOR_ATTACH,
        g.KE_RENDER_GRAPH_USAGE_DEPTH_READ, g.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE => gpu.KE_GPU_TEXTURE_USAGE_DEPTH_ATTACH,
        g.KE_RENDER_GRAPH_USAGE_COPY_SRC => gpu.KE_GPU_TEXTURE_USAGE_COPY_SRC,
        g.KE_RENDER_GRAPH_USAGE_COPY_DST => gpu.KE_GPU_TEXTURE_USAGE_COPY_DST,
        else => 0,
    };
}

fn bufferUsageOf(usage: g.ke_render_graph_usage) gpu.ke_gpu_buffer_usage {
    return switch (usage) {
        g.KE_RENDER_GRAPH_USAGE_STORAGE_READ, g.KE_RENDER_GRAPH_USAGE_STORAGE_WRITE => gpu.KE_GPU_BUFFER_USAGE_STORAGE,
        g.KE_RENDER_GRAPH_USAGE_VERTEX => gpu.KE_GPU_BUFFER_USAGE_VERTEX,
        g.KE_RENDER_GRAPH_USAGE_INDEX => gpu.KE_GPU_BUFFER_USAGE_INDEX,
        g.KE_RENDER_GRAPH_USAGE_INDIRECT => gpu.KE_GPU_BUFFER_USAGE_INDIRECT,
        g.KE_RENDER_GRAPH_USAGE_UNIFORM => gpu.KE_GPU_BUFFER_USAGE_UNIFORM,
        g.KE_RENDER_GRAPH_USAGE_COPY_SRC => gpu.KE_GPU_BUFFER_USAGE_COPY_SRC,
        g.KE_RENDER_GRAPH_USAGE_COPY_DST => gpu.KE_GPU_BUFFER_USAGE_COPY_DST,
        else => 0,
    };
}

fn earlierPoint(s: *State, a: u32, b: u32) bool {
    return s.passes.items[a].desc.injection_point < s.passes.items[b].desc.injection_point;
}

fn compileAll(s: *State) R.Error!void {
    s.order.clearRetainingCapacity();
    const count = s.passes.items.len;
    for (s.passes.items) |*p| {
        p.preds.clearRetainingCapacity();
        p.needed = false;
        p.root = false;
        p.alive = if (p.desc.condition) |condition| condition(p.desc.user) else true;
    }
    const sequence = gpa.alloc(u32, count) catch return error.OutOfMemory;
    defer gpa.free(sequence);
    for (sequence, 0..) |*slot, i| slot.* = @intCast(i);
    std.sort.insertion(u32, sequence, s, earlierPoint);
    for (s.resources.items, 1..) |*r, id| {
        var last_writer: ?u32 = null;
        var readers: std.ArrayList(u32) = .empty;
        defer readers.deinit(gpa);
        for (sequence) |i| {
            const p = &s.passes.items[i];
            if (!p.alive) continue;
            var reads_it = false;
            var writes_it = false;
            for (p.uses) |u| if (u.resource == id) {
                if (writes(u.usage)) writes_it = true else reads_it = true;
            };
            if (!reads_it and !writes_it) continue;
            if (last_writer) |w| if (w != i) try link(s, w, i);
            if (writes_it) {
                for (readers.items) |reader| if (reader != i) try link(s, reader, i);
                readers.clearRetainingCapacity();
                last_writer = i;
                if (r.imported or r.exported != null) p.root = true;
            } else readers.append(gpa, i) catch return error.OutOfMemory;
        }
    }
    for (s.passes.items, 0..) |*p, i| if (p.alive and (p.root or p.desc.side_effect)) markNeeded(s, @intCast(i));

    const placed = gpa.alloc(bool, count) catch return error.OutOfMemory;
    defer gpa.free(placed);
    @memset(placed, false);
    var wanted: usize = 0;
    for (s.passes.items) |p| if (p.alive and p.needed) {
        wanted += 1;
    };
    while (s.order.items.len < wanted) {
        var best: ?u32 = null;
        for (s.passes.items, 0..) |p, index| {
            const i: u32 = @intCast(index);
            if (!p.alive or !p.needed or placed[i]) continue;
            const ready = for (p.preds.items) |pred| {
                if (!placed[pred]) break false;
            } else true;
            if (!ready) continue;
            if (best == null or p.desc.injection_point < s.passes.items[best.?].desc.injection_point) best = i;
        }
        const next = best orelse {
            for (s.passes.items, 0..) |p, i| if (p.alive and p.needed and !placed[i]) log.warn("render graph: pass {s} is in a cycle", .{p.name});
            return error.General;
        };
        placed[next] = true;
        s.order.append(gpa, next) catch return error.OutOfMemory;
    }

    for (s.resources.items) |*r| {
        r.texture_usage = 0;
        r.buffer_usage = 0;
    }
    for (s.order.items) |index| for (s.passes.items[index].uses) |u| {
        const r = resourceOf(s, u.resource).?;
        r.texture_usage |= textureUsageOf(u.usage);
        r.buffer_usage |= bufferUsageOf(u.usage);
    };
    for (s.resources.items) |*r| if (r.kind == g.KE_RENDER_GRAPH_RESOURCE_TEXTURE and !r.imported) {
        const size = sizeOf(s, r, 0);
        r.width = size[0];
        r.height = size[1];
    };
}

/// Slot `compile`.
fn compile(self: ?*g.ke_render_graph) callconv(.c) Result {
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    compileAll(s) catch |err| return R.code(err);
    s.compiled = true;
    return R.ok;
}

fn make(s: *State, r: *Resource) R.Error!void {
    if (!r.owned or r.texture != invalid or r.buffer != invalid) return;
    switch (r.kind) {
        g.KE_RENDER_GRAPH_RESOURCE_TEXTURE => {
            if (r.texture_usage == 0) return;
            const d = r.texture_desc;
            const params: gpu.ke_gpu_texture_params = .{
                .label = r.name.ptr,
                .width = r.width,
                .height = r.height,
                .depth_or_array_layers = d.array_layers,
                .format = d.format,
                .dimension = gpu.KE_GPU_TEXTURE_DIM_2D,
                .usage = r.texture_usage,
                .mip_level_count = @intCast(d.mip_levels),
                .sample_count = @intCast(d.samples),
            };
            try R.check(s.device.create_texture.?(s.device, &params, &r.texture));
            try R.check(s.device.create_texture_view.?(s.device, r.texture, null, &r.view));
        },
        g.KE_RENDER_GRAPH_RESOURCE_BUFFER => {
            if (r.buffer_usage == 0) return;
            const params: gpu.ke_gpu_buffer_params = .{ .label = r.name.ptr, .size = @intCast(r.buffer_size), .usage = r.buffer_usage };
            try R.check(s.device.create_buffer.?(s.device, &params, &r.buffer));
        },
        else => {},
    }
}

fn isDepth(format: gpu.ke_gpu_texture_format) bool {
    return format == gpu.KE_GPU_TEXTURE_FORMAT_D16_UNORM or format == gpu.KE_GPU_TEXTURE_FORMAT_D24_UNORM_S8_UINT or format == gpu.KE_GPU_TEXTURE_FORMAT_D32_FLOAT or format == gpu.KE_GPU_TEXTURE_FORMAT_D32_FLOAT_S8_UINT;
}

/// The view of a use: the texture's own, or one made for the use's subresource or format.
fn viewOf(s: *State, r: *Resource, u: g.ke_render_graph_use) R.Error!u64 {
    if (u.base_mip == 0 and u.mip_count == 0 and u.base_layer == 0 and u.layer_count == 0 and u.view_format == gpu.KE_GPU_TEXTURE_FORMAT_INVALID) return r.view;
    if (r.texture == invalid) return r.view;
    const params: gpu.ke_gpu_texture_view_params = .{
        .label = r.name.ptr,
        .format = if (u.view_format == gpu.KE_GPU_TEXTURE_FORMAT_INVALID) r.texture_desc.format else u.view_format,
        .dimension = gpu.KE_GPU_TEXTURE_DIM_2D,
        .aspect = if (isDepth(r.texture_desc.format)) gpu.KE_GPU_TEXTURE_ASPECT_DEPTH else gpu.KE_GPU_TEXTURE_ASPECT_COLOR,
        .base_mip_level = @intCast(u.base_mip),
        .mip_level_count = @intCast(if (u.mip_count == 0) r.texture_desc.mip_levels -| u.base_mip else u.mip_count),
        .base_array_layer = @intCast(u.base_layer),
        .array_layer_count = @intCast(if (u.layer_count == 0) r.texture_desc.array_layers -| u.base_layer else u.layer_count),
    };
    var view: u64 = invalid;
    try R.check(s.device.create_texture_view.?(s.device, r.texture, &params, &view));
    s.views.append(gpa, view) catch {
        s.device.destroy_texture_view.?(s.device, view);
        return error.OutOfMemory;
    };
    return view;
}

fn loadOp(load: g.ke_render_graph_load) gpu.ke_gpu_load_op {
    return switch (load) {
        g.KE_RENDER_GRAPH_LOAD_CLEAR => gpu.KE_GPU_LOAD_OP_CLEAR,
        g.KE_RENDER_GRAPH_LOAD_DONT_CARE => gpu.KE_GPU_LOAD_OP_DONT_CARE,
        else => gpu.KE_GPU_LOAD_OP_LOAD,
    };
}

const max_color_attachments = 8;

fn recordRaster(s: *State, p: *Pass, encoder: *gpu.ke_gpu_command_encoder) R.Error!Result {
    var colors: [max_color_attachments]gpu.ke_gpu_color_attachment = undefined;
    var color_count: u32 = 0;
    var depth: gpu.ke_gpu_depth_stencil_attachment = undefined;
    var has_depth = false;
    for (p.uses) |u| {
        const r = resourceOf(s, u.resource).?;
        switch (u.usage) {
            g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT => {
                if (color_count == max_color_attachments) return error.InvalidArgument;
                colors[color_count] = .{ .view = try viewOf(s, r, u), .load_op = loadOp(u.load), .store_op = gpu.KE_GPU_STORE_OP_STORE, .clear_value = .{ .color = u.clear_color } };
                color_count += 1;
            },
            g.KE_RENDER_GRAPH_USAGE_DEPTH_WRITE, g.KE_RENDER_GRAPH_USAGE_DEPTH_READ => {
                const read_only = u.usage == g.KE_RENDER_GRAPH_USAGE_DEPTH_READ;
                depth = .{ .view = try viewOf(s, r, u), .depth_load_op = loadOp(u.load), .depth_store_op = gpu.KE_GPU_STORE_OP_STORE, .stencil_store_op = gpu.KE_GPU_STORE_OP_STORE, .clear_depth = u.clear_depth, .clear_stencil = @intCast(u.clear_stencil & 0xff), .depth_read_only = read_only, .stencil_read_only = read_only };
                has_depth = true;
            },
            else => {},
        }
    }
    const params: gpu.ke_gpu_render_pass_params = .{ .label = p.name.ptr, .color_attachments = &colors, .color_attachment_count = color_count, .depth_stencil_attachment = if (has_depth) &depth else null };
    const pass = encoder.begin_render_pass.?(encoder, &params) orelse return error.General;
    s.render_pass = pass;
    defer s.render_pass = null;
    const result = p.desc.record.?(p.desc.user, &s.ctx);
    pass.end.?(pass);
    return result;
}

fn recordOne(s: *State, p: *Pass, encoder: *gpu.ke_gpu_command_encoder) R.Error!Result {
    s.current = p;
    defer s.current = null;
    switch (p.desc.type) {
        g.KE_RENDER_GRAPH_PASS_RASTER => return recordRaster(s, p, encoder),
        g.KE_RENDER_GRAPH_PASS_COMPUTE => {
            const params: gpu.ke_gpu_compute_pass_params = .{ .label = p.name.ptr };
            const pass = encoder.begin_compute_pass.?(encoder, &params) orelse return error.General;
            s.compute_pass = pass;
            defer s.compute_pass = null;
            const result = p.desc.record.?(p.desc.user, &s.ctx);
            pass.end.?(pass);
            return result;
        },
        else => {
            s.encoder = encoder;
            defer s.encoder = null;
            return p.desc.record.?(p.desc.user, &s.ctx);
        },
    }
}

fn executeAll(s: *State) R.Error!Result {
    for (s.order.items) |index| for (s.passes.items[index].uses) |u| try make(s, resourceOf(s, u.resource).?);
    var handle = std.mem.zeroes(gpu.ke_gpu_command_encoder_handle);
    try R.check(s.device.create_command_encoder.?(s.device, null, &handle));
    defer handle.destroy.?(handle.ref);
    const encoder = handle.ref orelse return error.General;
    var first_failure: Result = R.ok;
    for (s.order.items) |index| {
        const result = try recordOne(s, &s.passes.items[index], encoder);
        if (result != R.ok and first_failure == R.ok) first_failure = result;
    }
    var buffer = std.mem.zeroes(gpu.ke_gpu_command_buffer_handle);
    try R.check(encoder.finish.?(encoder, &buffer));
    defer if (buffer.destroy) |d| d(buffer.ref);
    const cmds = [_]?*gpu.ke_gpu_command_buffer{buffer.ref};
    s.device.queue_submit.?(s.device, s.device.get_default_queue.?(s.device), &cmds, 1);
    for (s.resources.items) |*r| if (r.exported) |e| {
        const kept = s.exports.getPtr(e) orelse continue;
        if (kept.texture != r.texture or kept.buffer != r.buffer) {
            freeExport(s, kept.*);
            kept.* = .{ .kind = r.kind, .texture = r.texture, .view = r.view, .buffer = r.buffer, .format = r.texture_desc.format, .width = r.width, .height = r.height, .size = r.buffer_size };
        }
        r.owned = false;
    };
    return first_failure;
}

/// Slot `poll` of a `Done`.
fn donePoll(self: ?*Completion, out_result: ?*Result) callconv(.c) bool {
    const d: *Done = @ptrCast(@alignCast(self.?));
    if (out_result) |r| r.* = d.result;
    return true;
}

/// Slot `wait` of a `Done`.
fn doneWait(self: ?*Completion) callconv(.c) Result {
    const d: *Done = @ptrCast(@alignCast(self.?));
    return d.result;
}

/// Slot `release` of a `Done`.
fn doneRelease(self: ?*Completion) callconv(.c) void {
    const d: *Done = @ptrCast(@alignCast(self orelse return));
    gpa.destroy(d);
}

/// Slot `execute`: records and submits on the calling thread, so the completion is finished when it returns.
fn execute(self: ?*g.ke_render_graph, out_completion: ?*?*Completion) callconv(.c) Result {
    const out = out_completion orelse return R.code(error.InvalidArgument);
    out.* = null;
    const s = stateOf(self) orelse return R.code(error.InvalidArgument);
    if (!s.compiled) return R.code(error.NotSupported);
    const done = gpa.create(Done) catch return R.code(error.OutOfMemory);
    const result = executeAll(s) catch |err| {
        gpa.destroy(done);
        log.warn("render graph: executing the frame failed: {t}", .{err});
        return R.code(err);
    };
    done.* = .{ .api = .{ .handle = done, .poll = donePoll, .wait = doneWait, .release = doneRelease }, .result = result };
    out.* = &done.api;
    return R.ok;
}

fn ctxState(self: ?*g.ke_render_graph_ctx) ?*State {
    return @ptrCast(@alignCast((self orelse return null).handle orelse return null));
}

fn declared(s: *State, id: ResourceId) ?*Resource {
    const p = s.current orelse return null;
    for (p.uses) |u| if (u.resource == id) return resourceOf(s, id);
    return null;
}

/// Slot `encoder` of the context.
fn ctxEncoder(self: ?*g.ke_render_graph_ctx) callconv(.c) ?*gpu.ke_gpu_command_encoder {
    return (ctxState(self) orelse return null).encoder;
}

/// Slot `render_pass` of the context.
fn ctxRenderPass(self: ?*g.ke_render_graph_ctx) callconv(.c) ?*gpu.ke_gpu_render_pass {
    return (ctxState(self) orelse return null).render_pass;
}

/// Slot `compute_pass` of the context.
fn ctxComputePass(self: ?*g.ke_render_graph_ctx) callconv(.c) ?*gpu.ke_gpu_compute_pass {
    return (ctxState(self) orelse return null).compute_pass;
}

/// Slot `texture` of the context.
fn ctxTexture(self: ?*g.ke_render_graph_ctx, id: ResourceId) callconv(.c) u64 {
    const s = ctxState(self) orelse return invalid;
    return (declared(s, id) orelse return invalid).texture;
}

/// Slot `texture_view` of the context.
fn ctxTextureView(self: ?*g.ke_render_graph_ctx, id: ResourceId) callconv(.c) u64 {
    const s = ctxState(self) orelse return invalid;
    return (declared(s, id) orelse return invalid).view;
}

/// Slot `buffer` of the context.
fn ctxBuffer(self: ?*g.ke_render_graph_ctx, id: ResourceId) callconv(.c) u64 {
    const s = ctxState(self) orelse return invalid;
    return (declared(s, id) orelse return invalid).buffer;
}

/// The handle's `destroy`: frees the frame and every export.
fn destroy(self: ?*g.ke_render_graph) callconv(.c) void {
    const s = stateOf(self) orelse return;
    freeFrame(s);
    var it = s.exports.valueIterator();
    while (it.next()) |e| freeExport(s, e.*);
    s.exports.deinit(gpa);
    s.resources.deinit(gpa);
    s.passes.deinit(gpa);
    s.order.deinit(gpa);
    s.views.deinit(gpa);
    gpa.destroy(s);
}

export fn ke_render_graph_simple_create(device_in: ?*gpu.ke_gpu_device, out_graph: ?*g.ke_render_graph_handle) callconv(.c) Result {
    const out = out_graph orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(g.ke_render_graph_handle);
    const device = device_in orelse return R.code(error.InvalidArgument);
    const s = gpa.create(State) catch return R.code(error.OutOfMemory);
    s.* = .{
        .api = .{
            .begin_frame = beginFrame,
            .create_texture = createTexture,
            .create_buffer = createBuffer,
            .create_token = createToken,
            .import_texture = importTexture,
            .import_buffer = importBuffer,
            .export_resource = exportResource,
            .import_export = importExport,
            .release_export = releaseExport,
            .add_pass = addPass,
            .compile = compile,
            .execute = execute,
        },
        .device = device,
    };
    s.api.handle = s;
    s.ctx = .{ .handle = s, .encoder = ctxEncoder, .render_pass = ctxRenderPass, .compute_pass = ctxComputePass, .texture = ctxTexture, .texture_view = ctxTextureView, .buffer = ctxBuffer };
    out.* = .{ .ref = &s.api, .destroy = destroy };
    return R.ok;
}

test {
    _ = @import("render_graph_simple_test.zig");
}
