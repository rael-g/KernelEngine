const std = @import("std");
const rc = @import("render_service.zig");
const c = rc.c;

const MAX_COLOR_TARGETS = 8; // mirrors ke_gpu_render_pipeline_params.color_target_formats[8]

const PsoKey = struct {
    vertex_module: c.ke_gpu_shader_module,
    fragment_module: c.ke_gpu_shader_module,
    vertex_entry: [64]u8,
    fragment_entry: [64]u8,
    primitive_topology: c.ke_gpu_primitive_topology,
    cull_mode: c.ke_gpu_cull_mode,
    front_face: c.ke_gpu_front_face,
    vertex_buffer_count: u32,
    vertex_buffers_ptr: usize, // vertex_buffers is caller-owned + stable for the module's lifetime; compare by identity
    blend_state: c.ke_gpu_blend_state,
    depth_stencil: c.ke_gpu_depth_stencil_state,
    bind_group_layouts: [4]c.ke_gpu_bind_group_layout,
    bind_group_layout_count: u32,
    alpha_to_coverage_enabled: c.ke_bool,
    color_target_formats: [MAX_COLOR_TARGETS]c.ke_gpu_texture_format,
    color_target_count: u32,

    fn fromParams(p: *const c.ke_gpu_render_pipeline_params) PsoKey {
        var key: PsoKey = std.mem.zeroes(PsoKey);
        key.vertex_module = p.vertex_module;
        key.fragment_module = p.fragment_module;
        copyEntry(&key.vertex_entry, p.vertex_entry);
        copyEntry(&key.fragment_entry, p.fragment_entry);
        key.primitive_topology = p.primitive_topology;
        key.cull_mode = p.cull_mode;
        key.front_face = p.front_face;
        key.vertex_buffer_count = p.vertex_buffer_count;
        key.vertex_buffers_ptr = @intFromPtr(p.vertex_buffers);
        key.blend_state = p.blend_state;
        key.depth_stencil = p.depth_stencil;
        key.bind_group_layouts = p.bind_group_layouts;
        key.bind_group_layout_count = p.bind_group_layout_count;
        key.alpha_to_coverage_enabled = p.alpha_to_coverage_enabled;
        key.color_target_formats = p.color_target_formats;
        key.color_target_count = p.color_target_count;
        return key;
    }
};

fn copyEntry(dst: *[64]u8, src: [*c]const u8) void {
    if (src == null) return;
    const span = std.mem.span(src);
    const n = @min(span.len, dst.len - 1);
    @memcpy(dst[0..n], span[0..n]);
}

const PipelineState = enum(u8) { pending, ready };

const Entry = struct {
    state: std.atomic.Value(PipelineState),
    real_pso: c.ke_gpu_pipeline, // KE_GPU_INVALID_HANDLE until state == .ready
    fallback_pso: c.ke_gpu_pipeline, // magenta stand-in, bound while .pending
};

const CompileCtx = struct {
    entry: *Entry,
};

fn onRealPipelineReady(pso: c.ke_gpu_pipeline, user: ?*anyopaque) callconv(.c) void {
    const ctx: *CompileCtx = @ptrCast(@alignCast(user.?));
    if (pso != c.KE_GPU_INVALID_HANDLE) {
        ctx.entry.real_pso = pso;
        ctx.entry.state.store(.ready, .release);
    }
    std.heap.c_allocator.destroy(ctx);
}

pub const PipelineCache = struct {
    map: std.AutoHashMap(PsoKey, *Entry),
    magenta_fs: [MAX_COLOR_TARGETS]c.ke_gpu_shader_module,

    pub fn init() PipelineCache {
        return .{
            .map = std.AutoHashMap(PsoKey, *Entry).init(std.heap.c_allocator),
            .magenta_fs = [_]c.ke_gpu_shader_module{c.KE_GPU_INVALID_HANDLE} ** MAX_COLOR_TARGETS,
        };
    }

    pub fn destroyAll(self: *PipelineCache, device: *c.ke_gpu_device) void {
        var it = self.map.valueIterator();
        while (it.next()) |entry_ptr| {
            const e = entry_ptr.*;
            if (e.state.load(.acquire) == .ready) device.destroy_pipeline.?(device, e.real_pso);
            device.destroy_pipeline.?(device, e.fallback_pso);
            std.heap.c_allocator.destroy(e);
        }
        self.map.deinit();
        for (&self.magenta_fs) |*h| {
            if (h.* != c.KE_GPU_INVALID_HANDLE) device.destroy_shader_module.?(device, h.*);
            h.* = c.KE_GPU_INVALID_HANDLE;
        }
    }
};

fn magentaFragmentModule(st: *rc.CoreState, target_count: u32) c.ke_gpu_shader_module {
    const n = @max(@min(target_count, MAX_COLOR_TARGETS), 1);
    const idx = n - 1;
    if (st.pipeline_cache.magenta_fs[idx] != c.KE_GPU_INVALID_HANDLE) return st.pipeline_cache.magenta_fs[idx];

    var buf: [2048]u8 = undefined;
    var w = std.Io.Writer.fixed(&buf);
    if (n == 1) {
        w.writeAll("@fragment fn fs_main() -> @location(0) vec4f { return vec4f(1.0, 0.0, 1.0, 1.0); }\n") catch {};
    } else {
        w.writeAll("struct FSOut {\n") catch {};
        for (0..n) |i| w.print("  @location({d}) c{d}: vec4f,\n", .{ i, i }) catch {};
        w.writeAll("}\n@fragment fn fs_main() -> FSOut {\n  var o: FSOut;\n") catch {};
        for (0..n) |i| w.print("  o.c{d} = vec4f(1.0, 0.0, 1.0, 1.0);\n", .{i}) catch {};
        w.writeAll("  return o;\n}\n") catch {};
    }
    const src = w.buffered();
    const h = st.device.create_shader_module.?(st.device, &c.ke_gpu_shader_module_params{
        .code = src.ptr,
        .byte_size = src.len,
        .entry_point = "fs_main",
    }, null);
    st.pipeline_cache.magenta_fs[idx] = h;
    return h;
}

fn buildFallback(st: *rc.CoreState, params: [*c]const c.ke_gpu_render_pipeline_params) c.ke_gpu_pipeline {
    const p = @as(*const c.ke_gpu_render_pipeline_params, @ptrCast(params));
    var fallback_params = p.*;
    fallback_params.fragment_module = magentaFragmentModule(st, p.color_target_count);
    fallback_params.fragment_entry = "fs_main";
    return st.device.create_render_pipeline.?(st.device, &fallback_params);
}

pub fn getOrCreatePipeline(self: [*c]c.ke_render_service, params: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
    const st = rc.coreOf(self);
    const key = PsoKey.fromParams(params);

    if (st.pipeline_cache.map.get(key)) |entry| {
        return if (entry.state.load(.acquire) == .ready) entry.real_pso else entry.fallback_pso;
    }

    const entry = std.heap.c_allocator.create(Entry) catch {
        return st.device.create_render_pipeline.?(st.device, params);
    };
    entry.* = .{
        .state = std.atomic.Value(PipelineState).init(.pending),
        .real_pso = c.KE_GPU_INVALID_HANDLE,
        .fallback_pso = buildFallback(st, params),
    };

    st.pipeline_cache.map.put(key, entry) catch {
        st.device.destroy_pipeline.?(st.device, entry.fallback_pso);
        std.heap.c_allocator.destroy(entry);
        return st.device.create_render_pipeline.?(st.device, params);
    };

    const ctx = std.heap.c_allocator.create(CompileCtx) catch {
        return entry.fallback_pso;
    };
    ctx.* = .{ .entry = entry };
    st.device.create_render_pipeline_async.?(st.device, params, onRealPipelineReady, ctx);

    return entry.fallback_pso;
}
