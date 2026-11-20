const std = @import("std");
const testing = std.testing;

const abi_completion = @import("abi_completion");
const abi_render_gpu = @import("abi_render_gpu");
const abi_render_graph = @import("abi_render_graph");
const abi_result = @import("abi_result");
const heap = @import("heap");
const R = @import("result").Result(.{});
const graph = @import("render_graph_simple.zig");

const g = abi_render_graph.c;
const gpu = abi_render_gpu.c;
const Result = abi_result.c.ke_result;

const Device = struct {
    api: gpu.ke_gpu_device,
    encoder: gpu.ke_gpu_command_encoder,
    render_pass: gpu.ke_gpu_render_pass,
    compute_pass: gpu.ke_gpu_compute_pass,
    next: u64 = 1,
    textures: u32 = 0,
    destroyed_textures: u32 = 0,
    views: u32 = 0,
    destroyed_views: u32 = 0,
    submits: u32 = 0,
    last_width: u32 = 0,
    last_clear: [4]f32 = .{ 0, 0, 0, 0 },
    last_load: gpu.ke_gpu_load_op = 0,
    color_count: u32 = 0,

    var current: *Device = undefined;

    fn init(d: *Device) void {
        d.* = .{ .api = std.mem.zeroes(gpu.ke_gpu_device), .encoder = std.mem.zeroes(gpu.ke_gpu_command_encoder), .render_pass = std.mem.zeroes(gpu.ke_gpu_render_pass), .compute_pass = std.mem.zeroes(gpu.ke_gpu_compute_pass) };
        current = d;
        d.api.create_texture = createTexture;
        d.api.create_texture_view = createTextureView;
        d.api.create_buffer = createBuffer;
        d.api.destroy_texture = destroyTexture;
        d.api.destroy_texture_view = destroyTextureView;
        d.api.destroy_buffer = destroyBuffer;
        d.api.create_command_encoder = createEncoder;
        d.api.get_default_queue = defaultQueue;
        d.api.queue_submit = submit;
        d.encoder.begin_render_pass = beginRender;
        d.encoder.begin_compute_pass = beginCompute;
        d.encoder.finish = finish;
        d.render_pass.end = endRender;
        d.compute_pass.end = endCompute;
    }

    fn createTexture(_: ?*gpu.ke_gpu_device, p: ?*const gpu.ke_gpu_texture_desc, out: ?*u64) callconv(.c) Result {
        current.textures += 1;
        current.last_width = p.?.width;
        out.?.* = current.next;
        current.next += 1;
        return R.ok;
    }
    fn createTextureView(_: ?*gpu.ke_gpu_device, _: u64, _: ?*const gpu.ke_gpu_texture_view_desc, out: ?*u64) callconv(.c) Result {
        current.views += 1;
        out.?.* = current.next;
        current.next += 1;
        return R.ok;
    }
    fn createBuffer(_: ?*gpu.ke_gpu_device, _: ?*const gpu.ke_gpu_buffer_desc, out: ?*u64) callconv(.c) Result {
        out.?.* = current.next;
        current.next += 1;
        return R.ok;
    }
    fn destroyTexture(_: ?*gpu.ke_gpu_device, _: u64) callconv(.c) void {
        current.destroyed_textures += 1;
    }
    fn destroyTextureView(_: ?*gpu.ke_gpu_device, _: u64) callconv(.c) void {
        current.destroyed_views += 1;
    }
    fn destroyBuffer(_: ?*gpu.ke_gpu_device, _: u64) callconv(.c) void {}
    fn createEncoder(_: ?*gpu.ke_gpu_device, _: [*c]const u8, out: ?*gpu.ke_gpu_command_encoder_handle) callconv(.c) Result {
        out.?.* = .{ .ref = &current.encoder, .destroy = destroyEncoder };
        return R.ok;
    }
    fn destroyEncoder(_: ?*gpu.ke_gpu_command_encoder) callconv(.c) void {}
    fn defaultQueue(_: ?*gpu.ke_gpu_device) callconv(.c) u64 {
        return 1;
    }
    fn submit(_: ?*gpu.ke_gpu_device, _: u64, _: ?[*]const ?*gpu.ke_gpu_command_buffer, _: u32) callconv(.c) void {
        current.submits += 1;
    }
    fn beginRender(_: ?*gpu.ke_gpu_command_encoder, p: ?*const gpu.ke_gpu_render_pass_desc) callconv(.c) ?*gpu.ke_gpu_render_pass {
        if (p.?.color_attachment_count > 0) {
            current.color_count = p.?.color_attachment_count;
            current.last_clear = p.?.color_attachments.?[0].clear_value.color;
            current.last_load = p.?.color_attachments.?[0].load_op;
        }
        return &current.render_pass;
    }
    fn beginCompute(_: ?*gpu.ke_gpu_command_encoder, _: [*c]const u8) callconv(.c) ?*gpu.ke_gpu_compute_pass {
        return &current.compute_pass;
    }
    fn finish(_: ?*gpu.ke_gpu_command_encoder, out: ?*gpu.ke_gpu_command_buffer_handle) callconv(.c) Result {
        out.?.* = .{ .ref = null, .destroy = null };
        return R.ok;
    }
    fn endRender(_: ?*gpu.ke_gpu_render_pass) callconv(.c) void {}
    fn endCompute(_: ?*gpu.ke_gpu_compute_pass) callconv(.c) void {}
};

extern fn ke_render_graph_simple_create(?*gpu.ke_gpu_device, ?*g.ke_render_graph_handle) Result;

const Log = struct {
    var order: [16]u8 = undefined;
    var count: usize = 0;
    var seen: [16]u64 = undefined;
    var fail_with: Result = 0;
    fn reset() void {
        count = 0;
        fail_with = R.ok;
    }
};

fn recordTag(user: ?*anyopaque, ctx: ?*g.ke_render_graph_ctx) callconv(.c) Result {
    const tag: u8 = @intCast(@intFromPtr(user));
    Log.order[Log.count] = tag;
    Log.seen[Log.count] = ctx.?.texture.?(ctx, 1);
    Log.count += 1;
    return Log.fail_with;
}

fn tagUser(tag: u8) ?*anyopaque {
    return @ptrFromInt(@as(usize, tag));
}

const Fixture = struct {
    device: Device = undefined,
    handle: g.ke_render_graph_handle = undefined,

    fn init(f: *Fixture) !void {
        f.device.init();
        try R.check(ke_render_graph_simple_create(&f.device.api, &f.handle));
        try R.check(f.ref().begin_frame.?(f.ref(), 640, 480));
    }

    fn deinit(f: *Fixture) void {
        f.handle.destroy.?(f.handle.ref);
    }

    fn ref(f: *Fixture) *g.ke_render_graph {
        return f.handle.ref.?;
    }

    fn texture(f: *Fixture, class: g.ke_render_graph_size_class) !g.ke_render_graph_resource {
        var desc = std.mem.zeroes(g.ke_render_graph_texture_desc);
        desc.name = "target";
        desc.format = gpu.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
        desc.size_class = class;
        desc.width = 16;
        desc.height = 16;
        desc.scale_x = 0.5;
        desc.scale_y = 0.5;
        desc.mip_levels = 1;
        desc.array_layers = 1;
        desc.samples = 1;
        var id: g.ke_render_graph_resource = 0;
        try R.check(f.ref().create_texture.?(f.ref(), &desc, &id));
        return id;
    }

    fn pass(f: *Fixture, tag: u8, injection: u32, side_effect: bool, uses: []const g.ke_render_graph_use) !void {
        var desc = std.mem.zeroes(g.ke_render_graph_pass_desc);
        desc.name = "pass";
        desc.type = g.KE_RENDER_GRAPH_PASS_RASTER;
        desc.injection_point = injection;
        desc.side_effect = side_effect;
        desc.uses = uses.ptr;
        desc.use_count = @intCast(uses.len);
        desc.record = recordTag;
        desc.user = tagUser(tag);
        var id: g.ke_render_graph_pass = 0;
        try R.check(f.ref().add_pass.?(f.ref(), &desc, &id));
    }

    fn run(f: *Fixture) !Result {
        try R.check(f.ref().compile.?(f.ref()));
        var done: ?*abi_completion.c.ke_completion = null;
        try R.check(f.ref().execute.?(f.ref(), &done));
        defer done.?.release.?(done);
        var result: Result = R.code(error.General);
        try testing.expect(done.?.poll.?(done, &result));
        return result;
    }
};

fn use(resource: g.ke_render_graph_resource, usage: g.ke_render_graph_usage) g.ke_render_graph_use {
    var u = std.mem.zeroes(g.ke_render_graph_use);
    u.resource = resource;
    u.usage = usage;
    return u;
}

test "a pass whose writes no later pass reads is dropped, whatever its injection point" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    const target = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    const unused = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    try f.pass('r', 0, true, &.{use(target, g.KE_RENDER_GRAPH_USAGE_SAMPLED)});
    try f.pass('w', 9, false, &.{use(target, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT)});
    try f.pass('x', 1, false, &.{use(unused, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT)});
    try testing.expectEqual(R.ok, try f.run());
    try testing.expectEqualSlices(u8, "r", Log.order[0..Log.count]);
}

test "a use refers to the last write earlier in injection order, whatever the declaration order" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    const target = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    try f.pass('r', 9, true, &.{use(target, g.KE_RENDER_GRAPH_USAGE_SAMPLED)});
    try f.pass('u', 5, false, &.{use(target, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT)});
    try f.pass('w', 1, false, &.{use(target, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT)});
    try f.pass('a', 0, true, &.{});
    try testing.expectEqual(R.ok, try f.run());
    try testing.expectEqualSlices(u8, "awur", Log.order[0..Log.count]);
}

test "a raster pass records into a render pass begun with its cleared attachment, and sees only what it declared" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    const target = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    var u = use(target, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT);
    u.load = g.KE_RENDER_GRAPH_LOAD_CLEAR;
    u.clear_color = .{ 1, 0, 0, 1 };
    try f.pass('c', 0, true, &.{u});
    try f.pass('n', 1, true, &.{});
    try testing.expectEqual(R.ok, try f.run());
    try testing.expectEqual(@as(u32, 1), f.device.color_count);
    try testing.expectEqual(gpu.KE_GPU_LOAD_OP_CLEAR, f.device.last_load);
    try testing.expectEqual(@as(f32, 1), f.device.last_clear[0]);
    try testing.expect(Log.seen[0] != gpu.KE_GPU_INVALID_HANDLE);
    try testing.expectEqual(@as(u64, gpu.KE_GPU_INVALID_HANDLE), Log.seen[1]);
    try testing.expectEqual(@as(u32, 1), f.device.submits);
}

test "a texture relative to the output takes its scale of the output's size" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    const target = try f.texture(g.KE_RENDER_GRAPH_SIZE_OUTPUT_RELATIVE);
    try f.pass('w', 0, true, &.{use(target, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT)});
    _ = try f.run();
    try testing.expectEqual(@as(u32, 320), f.device.last_width);
}

test "a frame's textures are freed when the next begins, and an exported one is kept until released" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    const transient = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    const history = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    var kept: g.ke_render_graph_export = 0;
    try R.check(f.ref().export_resource.?(f.ref(), history, &kept));
    try f.pass('w', 0, true, &.{ use(transient, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT), use(history, g.KE_RENDER_GRAPH_USAGE_COLOR_ATTACHMENT) });
    _ = try f.run();
    try testing.expectEqual(@as(u32, 2), f.device.textures);
    try R.check(f.ref().begin_frame.?(f.ref(), 640, 480));
    try testing.expectEqual(@as(u32, 1), f.device.destroyed_textures);
    var again: g.ke_render_graph_resource = 0;
    try R.check(f.ref().import_export.?(f.ref(), kept, &again));
    try f.pass('r', 0, true, &.{use(again, g.KE_RENDER_GRAPH_USAGE_SAMPLED)});
    _ = try f.run();
    try testing.expectEqual(@as(u32, 2), f.device.textures);
    f.ref().release_export.?(f.ref(), kept);
    try testing.expectEqual(@as(u32, 2), f.device.destroyed_textures);
    try testing.expectEqual(R.code(error.NotFound), f.ref().import_export.?(f.ref(), kept, &again));
}

test "a record's failure is what the frame's completion carries" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    Log.reset();
    Log.fail_with = R.code(error.InvalidArgument);
    try f.pass('f', 0, true, &.{});
    try testing.expectEqual(R.code(error.InvalidArgument), try f.run());
    Log.reset();
}

test "what this graph does not offer is refused, and executing before compiling is not supported" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    const target = try f.texture(g.KE_RENDER_GRAPH_SIZE_ABSOLUTE);
    var desc = std.mem.zeroes(g.ke_render_graph_pass_desc);
    desc.record = recordTag;
    const readback = [_]g.ke_render_graph_use{use(target, g.KE_RENDER_GRAPH_USAGE_READBACK)};
    desc.uses = &readback;
    desc.use_count = 1;
    var id: g.ke_render_graph_pass = 0;
    try testing.expectEqual(R.code(error.NotSupported), f.ref().add_pass.?(f.ref(), &desc, &id));
    const vertex = [_]g.ke_render_graph_use{use(target, g.KE_RENDER_GRAPH_USAGE_VERTEX)};
    desc.uses = &vertex;
    try testing.expectEqual(R.code(error.InvalidArgument), f.ref().add_pass.?(f.ref(), &desc, &id));
    var mips = std.mem.zeroes(g.ke_render_graph_texture_desc);
    mips.format = gpu.KE_GPU_TEXTURE_FORMAT_RGBA8_UNORM;
    mips.width = 4;
    mips.height = 4;
    mips.mip_levels = 3;
    mips.array_layers = 1;
    mips.samples = 1;
    mips.generate_mips = true;
    var res: g.ke_render_graph_resource = 0;
    try testing.expectEqual(R.code(error.NotSupported), f.ref().create_texture.?(f.ref(), &mips, &res));
    var done: ?*abi_completion.c.ke_completion = null;
    try testing.expectEqual(R.code(error.NotSupported), f.ref().execute.?(f.ref(), &done));
}

var seen_size: u64 = 0;

fn recordSize(user: ?*anyopaque, ctx: ?*g.ke_render_graph_ctx) callconv(.c) Result {
    const id: g.ke_render_graph_resource = @intCast(@intFromPtr(user));
    seen_size = ctx.?.buffer_size.?(ctx, id);
    return R.ok;
}

test "a pass sees the size of a buffer it declared" {
    var f: Fixture = .{};
    try f.init();
    defer f.deinit();
    var id: g.ke_render_graph_resource = 0;
    try R.check(f.ref().import_buffer.?(f.ref(), 77, 256, &id));
    const uses = [_]g.ke_render_graph_use{use(id, g.KE_RENDER_GRAPH_USAGE_UNIFORM)};
    var desc = std.mem.zeroes(g.ke_render_graph_pass_desc);
    desc.name = "sized";
    desc.type = g.KE_RENDER_GRAPH_PASS_COPY;
    desc.side_effect = true;
    desc.uses = &uses;
    desc.use_count = uses.len;
    desc.record = recordSize;
    desc.user = @ptrFromInt(id);
    var pass: g.ke_render_graph_pass = 0;
    try R.check(f.ref().add_pass.?(f.ref(), &desc, &pass));
    seen_size = 0;
    try testing.expectEqual(R.ok, try f.run());
    try testing.expectEqual(@as(u64, 256), seen_size);
}

test "creating and destroying graphs leaves no block allocated" {
    var f: Fixture = .{};
    try f.init();
    f.deinit();
    try heap.expectNoLeaks();
}

comptime {
    _ = graph;
}
