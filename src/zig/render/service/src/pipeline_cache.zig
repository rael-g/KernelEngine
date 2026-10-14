//! Answers the render service's pipeline requests at once with a placeholder, and upgrades each to
//! the real pipeline once the device has compiled it.

const std = @import("std");
const heap = @import("heap");
const rc = @import("render_service.zig");
const c = rc.c;

const MAX_COLOR_TARGETS = 8;

/// The fields of a render pipeline params that decide which pipeline it is, copied so the key
/// outlives the params. The entry names are copied, but the vertex buffer array is kept only by
/// its address, so an identical array at another address makes another key.
const PsoKey = struct {
    vertex_module: c.ke_gpu_shader_module,
    fragment_module: c.ke_gpu_shader_module,
    vertex_entry: [64]u8,
    fragment_entry: [64]u8,
    primitive_topology: c.ke_gpu_primitive_topology,
    cull_mode: c.ke_gpu_cull_mode,
    front_face: c.ke_gpu_front_face,
    vertex_buffer_count: u32,
    vertex_buffers_ptr: usize,
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

/// One request for a distinct key. The fallback exists from creation; the real pipeline is written
/// by the device's callback and is read only through `current`. An entry is freed by `destroyAll`,
/// or by `getOrCreatePipeline` when another entry won its key.
const Entry = struct {
    key: PsoKey,
    hash: u64,
    state: std.atomic.Value(PipelineState),
    real_pso: c.ke_gpu_pipeline,
    fallback_pso: c.ke_gpu_pipeline,

    /// The acquire load pairs with the release store in `onRealPipelineReady`, so a reader that
    /// sees the real pipeline as current also sees its handle.
    fn current(self: *const Entry) c.ke_gpu_pipeline {
        return if (self.state.load(.acquire) == .ready) self.real_pso else self.fallback_pso;
    }
};

/// Called by the device, on whichever thread finished the compile, once the asynchronous request
/// made by `getOrCreatePipeline` finishes. An invalid pipeline is dropped, leaving the entry on its
/// fallback.
fn onRealPipelineReady(pso: c.ke_gpu_pipeline, user: ?*anyopaque) callconv(.c) void {
    const entry: *Entry = @ptrCast(@alignCast(user.?));
    if (pso == c.KE_GPU_INVALID_HANDLE) return;
    entry.real_pso = pso;
    entry.state.store(.ready, .release);
}

const hashKey = std.hash_map.getAutoHashFn(PsoKey, void);
const eqlKey = std.hash_map.getAutoEqlFn(PsoKey, void);

const first_capacity = 16;

/// A table of entries with open addressing and a count. Slots are written only while the snapshot
/// is being built, which is what lets readers search a published one without a lock.
/// `retired_next` is used only after the snapshot has been replaced, to link it onto the cache's
/// retired list.
const Snapshot = struct {
    slots: []?*Entry,
    count: usize,
    retired_next: ?*Snapshot,

    fn create(capacity: usize) ?*Snapshot {
        const snap = heap.gpa.create(Snapshot) catch return null;
        const slots = heap.gpa.alloc(?*Entry, capacity) catch {
            heap.gpa.destroy(snap);
            return null;
        };
        @memset(slots, null);
        snap.* = .{ .slots = slots, .count = 0, .retired_next = null };
        return snap;
    }

    fn destroy(self: *Snapshot) void {
        heap.gpa.free(self.slots);
        heap.gpa.destroy(self);
    }

    /// Probes from the hash's slot until an empty slot. `grownWith` grows a snapshot before it
    /// fills, so an empty slot always ends the probe.
    fn find(self: *const Snapshot, hash: u64, key: *const PsoKey) ?*Entry {
        const mask = self.slots.len - 1;
        var i: usize = @intCast(hash & mask);
        while (self.slots[i]) |e| : (i = (i + 1) & mask) {
            if (e.hash == hash and eqlKey({}, e.key, key.*)) return e;
        }
        return null;
    }

    /// Used only on a snapshot that no reader can see yet.
    fn place(self: *Snapshot, entry: *Entry) void {
        const mask = self.slots.len - 1;
        var i: usize = @intCast(entry.hash & mask);
        while (self.slots[i] != null) i = (i + 1) & mask;
        self.slots[i] = entry;
        self.count += 1;
    }

    /// Never changes the old snapshot, which a reader may still be searching. The new one is
    /// published only by `insert`.
    fn grownWith(self: ?*const Snapshot, entry: *Entry) ?*Snapshot {
        const have = if (self) |snap| snap.count else 0;
        var capacity: usize = if (self) |snap| snap.slots.len else first_capacity;
        while ((have + 1) * 2 > capacity) capacity *= 2;
        const next = Snapshot.create(capacity) orelse return null;
        if (self) |snap| {
            for (snap.slots) |slot| {
                if (slot) |e| next.place(e);
            }
        }
        next.place(entry);
        return next;
    }
};

/// The outcome of `PipelineCache.insert`: the entry was published, another entry already held its
/// key, or the grown snapshot could not be allocated.
const Insert = union(enum) {
    published,
    existing: *Entry,
    failed,
};

/// Holds the current snapshot, the retired snapshots and the fallback modules of one render
/// service. It is a field of the service's `CoreState`, and its contents are freed by
/// `destroyAll`.
pub const PipelineCache = struct {
    current: std.atomic.Value(?*Snapshot),
    retired: std.atomic.Value(?*Snapshot),
    magenta_fs: [MAX_COLOR_TARGETS]std.atomic.Value(c.ke_gpu_shader_module),

    pub fn init() PipelineCache {
        var cache: PipelineCache = .{
            .current = .init(null),
            .retired = .init(null),
            .magenta_fs = undefined,
        };
        for (&cache.magenta_fs) |*h| h.* = .init(c.KE_GPU_INVALID_HANDLE);
        return cache;
    }

    /// Takes no lock: it reads the snapshot that is current when the pointer is loaded.
    fn find(self: *PipelineCache, hash: u64, key: *const PsoKey) ?*Entry {
        const snap = self.current.load(.acquire) orelse return null;
        return snap.find(hash, key);
    }

    /// Publishes the entry unless another entry already holds its key, and returns that holder
    /// instead. When another insert publishes first, the search repeats on the newer snapshot.
    /// Returns the failed outcome when the grown snapshot cannot be allocated.
    fn insert(self: *PipelineCache, entry: *Entry) Insert {
        while (true) {
            const base = self.current.load(.acquire);
            if (base) |snap| {
                if (snap.find(entry.hash, &entry.key)) |winner| return .{ .existing = winner };
            }
            const next = Snapshot.grownWith(base, entry) orelse return .failed;
            if (self.current.cmpxchgStrong(base, next, .acq_rel, .acquire) == null) {
                if (base) |old| self.retire(old);
                return .published;
            }
            next.destroy();
        }
    }

    fn retire(self: *PipelineCache, snap: *Snapshot) void {
        var head = self.retired.load(.acquire);
        while (true) {
            snap.retired_next = head;
            head = self.retired.cmpxchgWeak(head, snap, .release, .acquire) orelse return;
        }
    }

    /// Frees the entries and their pipelines, every snapshot including the retired ones, and the
    /// fallback modules. Each one is taken out of the cache before it is freed, so calling it
    /// again frees nothing.
    pub fn destroyAll(self: *PipelineCache, device: *c.ke_gpu_device) void {
        if (self.current.swap(null, .acq_rel)) |snap| {
            for (snap.slots) |slot| {
                const e = slot orelse continue;
                if (e.state.load(.acquire) == .ready) device.destroy_pipeline.?(device, e.real_pso);
                device.destroy_pipeline.?(device, e.fallback_pso);
                heap.gpa.destroy(e);
            }
            snap.destroy();
        }
        var old = self.retired.swap(null, .acq_rel);
        while (old) |snap| {
            old = snap.retired_next;
            snap.destroy();
        }
        for (&self.magenta_fs) |*h| {
            const module = h.swap(c.KE_GPU_INVALID_HANDLE, .acq_rel);
            if (module != c.KE_GPU_INVALID_HANDLE) device.destroy_shader_module.?(device, module);
        }
    }
};

/// Every fallback of one target count shares one module, created on the first request for that
/// count and destroyed by `destroyAll`.
fn magentaFragmentModule(st: *rc.CoreState, target_count: u32) c.ke_gpu_shader_module {
    const n = @max(@min(target_count, MAX_COLOR_TARGETS), 1);
    const slot = &st.pipeline_cache.magenta_fs[n - 1];
    const existing = slot.load(.acquire);
    if (existing != c.KE_GPU_INVALID_HANDLE) return existing;

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
    const made = st.device.create_shader_module.?(st.device, &c.ke_gpu_shader_module_params{
        .code = src.ptr,
        .byte_size = src.len,
        .label = "service.fallback_fragment",
    }, null);
    if (made == c.KE_GPU_INVALID_HANDLE) return made;
    if (slot.cmpxchgStrong(c.KE_GPU_INVALID_HANDLE, made, .acq_rel, .acquire)) |won| {
        st.device.destroy_shader_module.?(st.device, made);
        return won;
    }
    return made;
}

/// The result is returned as it is, even when the device failed to create it: nothing here or in
/// `getOrCreatePipeline` checks it.
fn buildFallback(st: *rc.CoreState, params: [*c]const c.ke_gpu_render_pipeline_params) c.ke_gpu_pipeline {
    const p = @as(*const c.ke_gpu_render_pipeline_params, @ptrCast(params));
    var fallback_params = p.*;
    fallback_params.fragment_module = magentaFragmentModule(st, p.color_target_count);
    fallback_params.fragment_entry = "fs_main";
    return st.device.create_render_pipeline.?(st.device, &fallback_params);
}

/// Answers the render service's pipeline request. A key already in the table returns its current
/// pipeline. A new key returns its fallback while the real pipeline compiles, and the same key
/// returns the real pipeline once the device has delivered it. Only when the entry or the grown
/// table cannot be allocated is the pipeline created synchronously, and then it is not cached.
/// Callable from several workers at once without a lock: a request that loses the publication of
/// its entry destroys the fallback it built, never starts its compile, and answers with the
/// entry that won. A pipeline the device fails to compile leaves the entry on its fallback for
/// good. The vertex layout array of `params` is part of the key by address, so it has to live as
/// long as the requests that must share an entry.
pub fn getOrCreatePipeline(self: [*c]c.ke_render_service, params: [*c]const c.ke_gpu_render_pipeline_params) callconv(.c) c.ke_gpu_pipeline {
    const st = rc.coreOf(self);
    const key = PsoKey.fromParams(params);
    const hash = hashKey({}, key);

    if (st.pipeline_cache.find(hash, &key)) |entry| return entry.current();

    const entry = heap.gpa.create(Entry) catch {
        return st.device.create_render_pipeline.?(st.device, params);
    };
    entry.* = .{
        .key = key,
        .hash = hash,
        .state = std.atomic.Value(PipelineState).init(.pending),
        .real_pso = c.KE_GPU_INVALID_HANDLE,
        .fallback_pso = buildFallback(st, params),
    };

    switch (st.pipeline_cache.insert(entry)) {
        .published => {
            st.device.create_render_pipeline_async.?(st.device, params, onRealPipelineReady, entry);
            return entry.fallback_pso;
        },
        .existing => |winner| {
            st.device.destroy_pipeline.?(st.device, entry.fallback_pso);
            heap.gpa.destroy(entry);
            return winner.current();
        },
        .failed => {
            st.device.destroy_pipeline.?(st.device, entry.fallback_pso);
            heap.gpa.destroy(entry);
            return st.device.create_render_pipeline.?(st.device, params);
        },
    }
}
