const std = @import("std");
const cimport = @import("cimport.zig");
const shadow_module = @import("shadow_module.zig");
const ShadowModule = shadow_module.ShadowModule;
const skybox_module = @import("skybox_module.zig");
const SkyboxModule = skybox_module.SkyboxModule;
const cluster_module = @import("cluster_module.zig");
const ClusterModule = cluster_module.ClusterModule;
const forward_module = @import("forward_module.zig");
const ForwardModule = forward_module.ForwardModule;

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed. Shared with
// shadow_module.zig via cimport.zig — a second @cImport of the same headers
// would produce distinct, incompatible types for the same C struct.
pub const c = cimport.c;

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

// Only the tonemap pass's shaders live here now. Each feature pass embeds its
// own shaders in its own file: shadow_module.zig, skybox_module.zig,
// cluster_module.zig, and forward_module.zig (the forward_lit + magenta pair).
const tonemap_vs_wgsl = @embedFile("tonemap.vs.wgsl");
const tonemap_fs_wgsl = @embedFile("tonemap.fs.wgsl");

// Clustered-forward grid + per-froxel cap defaults. These are workload-tuning
// values the caller can override via ke_render_cluster_params (0 field = keep
// the default below) — not engine-imposed limits. A froxel holding more
// concurrently overlapping lights than max_lights_per_cluster silently drops
// the excess (a real correctness limit of the algorithm), so a caller running
// a denser scene than these defaults suit should raise the field rather than
// hit that ceiling. The grid/cull machinery itself lives in cluster_module.zig
// now; these defaults stay here because they're resolved from the caller's
// ke_render_cluster_params before cluster_module.setup is even called.
const DEFAULT_GRID_X: u32 = 32;
const DEFAULT_GRID_Y: u32 = 18;
const DEFAULT_GRID_Z: u32 = 24;
const DEFAULT_MAX_LIGHTS_PER_CLUSTER: u32 = 256;

// The device is borrowed (caller-owned); only the render core is owned here.
const ModuleState = struct {
    core: c.ke_render_core_handle,
    device: *c.ke_gpu_device,
    ndc: c.ke_ndc_convention, // backend clip-space convention (queried at setup)
    logger: ?*c.ke_logger, // borrowed, optional — runtime diagnostics route through it when present

    bb_writes: [1][*c]const u8,
    io: c.ke_render_pass_io,
    // Frame barrier: begin_frame WRITES "frame", every pass READS it, end_frame
    // WRITES it (write-after-read). W→R→W brackets all passes into one frame so
    // begin (clears the slot table + acquires the backbuffer) strictly precedes
    // every pass and end (submits) strictly follows; passes stay parallel (R/R).
    frame_cid: c.ke_component_id,
    begin_access: [2]c.ke_component_access, // WRITE backbuffer, WRITE frame
    clear_access: [2]c.ke_component_access, // WRITE backbuffer, READ frame
    end_access: [2]c.ke_component_access, // READ backbuffer, WRITE frame

    // Feature pass modules — each owns its own GPU resources, runtime system(s),
    // and shaders, in its own file. They are set up by ke_render_module_create
    // in dependency order (shadow + cluster + skybox first, then forward, which
    // borrows their handles). This aggregator holds them so their addresses are
    // stable for the pointers forward keeps and for the systems' user_data.
    shadow: ShadowModule,   // shadow_module.zig — depth pass, writes "shadow_map"
    cluster: ClusterModule, // cluster_module.zig — light cull compute, set-3 light lists
    skybox: SkyboxModule,   // skybox_module.zig — cubemap background, drawn inside forward's pass
    forward: ForwardModule, // forward_module.zig — the opaque forward+ shading pass (consumes the above)

    // ACES tonemapping pass — reads "hdr" (Rgba16Float), writes "backbuffer".
    tonemap_pipeline: c.ke_gpu_pipeline,
    tonemap_bgl: c.ke_gpu_bind_group_layout,
    tonemap_bind_group: c.ke_gpu_bind_group,
    tonemap_writes: [1][*c]const u8,
    tonemap_reads: [1][*c]const u8,
    tonemap_io: c.ke_render_pass_io,
    tonemap_access: [2]c.ke_component_access,

    // UI overlay — screen-space quads (Font/Label text, solid rects) composited
    // over the tonemapped scene. Loads (doesn't clear) the backbuffer; the core
    // owns the pipeline + per-frame quad list (ke_render_core.ui_quad/ui_draw).
    ui_writes: [1][*c]const u8,
    ui_io: c.ke_render_pass_io,
    ui_access: [1]c.ke_component_access,
};

inline fn stateOf(user: ?*anyopaque) *ModuleState {
    return @alignCast(@ptrCast(user.?));
}

// ── Frame-boundary systems (ordered by the backbuffer tag-cid) ────────────────

fn beginFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.begin_frame.?(st.core.ref, null);
}

fn clearSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const pc = st.core.ref.*.begin_pass.?(st.core.ref, ctx, &st.io);
    if (pc == null) return;
    const rp = pc.*.begin_render.?(pc);
    rp.*.end.?(rp);
    st.core.ref.*.end_pass.?(st.core.ref, pc);
}

fn endFrameSys(_: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    _ = st.core.ref.*.end_frame.?(st.core.ref, null);
}

// A GPU resource create call failed on a path with no out_error slot to bubble
// through (a runtime rebuild triggered by an environment change, not the
// initial setup path) — route the captured ke_error through the logger
// instead of losing it silently.
fn logGpuError(logger: ?*c.ke_logger, err: ?*c.ke_error, what: []const u8) void {
    const lg = logger orelse return;
    const e = err orelse return;
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "{s} failed: {s}", .{ what, e.message }) catch return;
    var ev = c.ke_log_event{ .level = c.KE_LOG_LEVEL_ERROR, .tag = "render_core", .message = msg.ptr };
    lg.log.?(lg, &ev);
}

// ── ACES tonemapping pass ─────────────────────────────────────────────────────
// Reads the HDR buffer written by the forward pass and resolves it to the
// swapchain via the ACES fitted curve (Narkowicz 2015).

fn tonemapSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    const core = st.core.ref;
    const dev = st.device;

    const pc = core.*.begin_pass.?(core, ctx, &st.tonemap_io);
    if (pc == null) return;

    // Resolve the HDR texture view for this frame and rebuild the bind group.
    const hdr_view = pc.*.read.?(pc, "hdr");
    const samp = core.*.sampler.?(core);
    const entries = [2]c.ke_gpu_bind_group_entry{
        .{ .binding = 0, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = hdr_view, .sampler = 0 },
        .{ .binding = 1, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .buffer = 0, .buffer_offset = 0, .buffer_size = 0, .texture_view = 0, .sampler = samp },
    };
    // Destroy the previous frame's bind group before creating the new one.
    if (st.tonemap_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, st.tonemap_bind_group);
    var err: ?*c.ke_error = null;
    st.tonemap_bind_group = dev.create_bind_group.?(dev, &c.ke_gpu_bind_group_params{
        .layout = st.tonemap_bgl,
        .entry_count = 2,
        .entries = &entries,
    }, &err);
    if (err != null) logGpuError(st.logger, err, "tonemap bind group");

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, st.tonemap_pipeline);
    rp.*.set_bind_group.?(rp, 0, st.tonemap_bind_group, null, 0);
    rp.*.draw.?(rp, 3, 1, 0, 0); // fullscreen triangle — no vertex buffer needed
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
}

// UI overlay pass — draws whatever ui_quad calls (Font/Label systems, game HUD
// code) queued this frame. The core owns the pipeline and quad list entirely;
// this just forwards ctx/io so ui_draw can begin/end its own pass.
fn uiSys(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32) callconv(.c) void {
    const st = stateOf(user);
    st.core.ref.*.ui_draw.?(st.core.ref, ctx, &st.ui_io);
}

fn tonemapSetup(st: *ModuleState, out_error: [*c][*c]c.ke_error) bool {
    const dev = st.device;

    const vs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_vs_wgsl), .byte_size = tonemap_vs_wgsl.len, .entry_point = "tonemap.vs" }, out_error);
    defer dev.destroy_shader_module.?(dev, vs);
    const fs = dev.create_shader_module.?(dev, &c.ke_gpu_shader_module_params{ .code = @ptrCast(tonemap_fs_wgsl), .byte_size = tonemap_fs_wgsl.len, .entry_point = "tonemap.fs" }, out_error);
    defer dev.destroy_shader_module.?(dev, fs);

    // Set 0: { texture2D t_hdr @binding(0), sampler s_hdr @binding(1) }
    const bgl_entries = [2]c.ke_gpu_bind_group_layout_entry{
        .{ .binding = 0, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_TEXTURE, .has_dynamic_offset = 0, .view_dimension = c.KE_GPU_TEXTURE_DIM_2D },
        .{ .binding = 1, .visibility = c.KE_GPU_SHADER_STAGE_FRAGMENT, .type = c.KE_GPU_BINDING_TYPE_SAMPLER, .has_dynamic_offset = 0, .view_dimension = 0 },
    };
    const bgl = dev.create_bind_group_layout.?(dev, &c.ke_gpu_bind_group_layout_params{
        .entry_count = 2,
        .entries = &bgl_entries,
    });

    st.tonemap_bgl = bgl; // kept alive for per-frame bind group creation in tonemapSys
    var pp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    pp.vertex_module   = vs;
    pp.vertex_entry    = "vs_main";
    pp.fragment_module = fs;
    pp.fragment_entry  = "fs_main";
    pp.bind_group_layouts[0] = bgl;
    pp.bind_group_layout_count = 1;
    pp.color_target_format = 0; // swapchain surface format
    pp.blend_state.write_mask = 0x0F;
    // no depth test — fullscreen triangle pass over backbuffer
    pp.depth_stencil.depth_test_enabled = 0;
    pp.depth_stencil.depth_write_enabled = 0;
    pp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_ALWAYS;
    st.tonemap_pipeline = dev.create_render_pipeline.?(dev, &pp);
    if (st.tonemap_pipeline == c.KE_GPU_INVALID_HANDLE) {
        dev.destroy_bind_group_layout.?(dev, bgl);
        return false;
    }

    st.tonemap_bind_group = c.KE_GPU_INVALID_HANDLE;

    st.tonemap_writes = .{"backbuffer"};
    st.tonemap_reads  = .{"hdr"};
    st.tonemap_io = std.mem.zeroes(c.ke_render_pass_io);
    st.tonemap_io.writes = @ptrCast(&st.tonemap_writes);
    st.tonemap_io.writes_count = 1;
    st.tonemap_io.reads = @ptrCast(&st.tonemap_reads);
    st.tonemap_io.reads_count = 1;
    st.tonemap_io.cmd_slot = 4; // after forward (slot 3)

    // "hdr" is declared by forward_module.setup (which runs first); resolve it
    // by name here rather than threading a cid across the module boundary.
    st.tonemap_access = .{
        .{ .cid = st.core.ref.*.cid.?(st.core.ref, "hdr"), .access = c.KE_ACCESS_READ },
        .{ .cid = st.core.ref.*.cid.?(st.core.ref, "backbuffer"), .access = c.KE_ACCESS_WRITE },
    };
    return true;
}

fn registerSys(rt: *c.ke_runtime, name: [*c]const u8,
               queries: [*c]const c.ke_query_decl, query_count: u32,
               access: [*c]const c.ke_component_access, access_count: u32,
               user: anytype, exec: ExecFn) void {
    var params = std.mem.zeroes(c.ke_runtime_system_params);
    params.name = name;
    params.phase = c.KE_PHASE_RENDER;
    params.queries = queries;
    params.query_count = query_count;
    params.access_list = access;
    params.access_count = access_count;
    params.pinned_thread = 0; // render systems run in parallel (sim ‖ render + parallel passes)
    params.user_data = user;
    params.execute = exec;
    _ = rt.register_system.?(rt, &params, null);
}

export fn ke_render_module_core(module: ?*c.ke_render_module) callconv(.c) ?*c.ke_render_core {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return null));
    return st.core.ref;
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    const dev = st.device;
    if (st.tonemap_bind_group != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group.?(dev, st.tonemap_bind_group);
    if (st.tonemap_bgl != c.KE_GPU_INVALID_HANDLE)
        dev.destroy_bind_group_layout.?(dev, st.tonemap_bgl);
    if (st.core.destroy) |d| d(st.core.ref);
    gpa.destroy(st);
}

const empty = c.ke_render_module_handle{ .ref = null, .destroy = null };

export fn ke_render_module_create(runtime: ?*c.ke_runtime, ecs: ?*c.ke_ecs, device: ?*c.ke_gpu_device,
                                  default_passes: c.ke_bool, logger: ?*c.ke_logger,
                                  cluster_params: ?*const c.ke_render_cluster_params,
                                  feature_params: ?*const c.ke_render_feature_params, out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_module_handle {
    const rt = runtime orelse return empty;
    const e = ecs orelse return empty;
    const dev = device orelse return empty;

    const core_h = c.ke_render_core_create(dev, e, out_error);
    if (core_h.ref == null) return empty;

    const st = gpa.create(ModuleState) catch {
        if (core_h.destroy) |d| d(core_h.ref);
        return empty;
    };
    st.core = core_h;
    st.device = dev;
    // 0 (or an absent params struct) means "use the engine default" per field —
    // a caller running a denser scene than the default sweet spot can raise
    // any of these rather than hit a hardcoded ceiling (§ no-magic-numbers).
    // Resolved here (rather than inside cluster_module.setup) because
    // ke_render_cluster_params is render_module.zig's own C ABI surface.
    var grid_x: u32 = undefined;
    var grid_y: u32 = undefined;
    var grid_z: u32 = undefined;
    var max_lights_per_cluster: u32 = undefined;
    if (cluster_params) |p| {
        grid_x = if (p.grid_x != 0) p.grid_x else DEFAULT_GRID_X;
        grid_y = if (p.grid_y != 0) p.grid_y else DEFAULT_GRID_Y;
        grid_z = if (p.grid_z != 0) p.grid_z else DEFAULT_GRID_Z;
        max_lights_per_cluster = if (p.max_lights_per_cluster != 0) p.max_lights_per_cluster else DEFAULT_MAX_LIGHTS_PER_CLUSTER;
    } else {
        grid_x = DEFAULT_GRID_X;
        grid_y = DEFAULT_GRID_Y;
        grid_z = DEFAULT_GRID_Z;
        max_lights_per_cluster = DEFAULT_MAX_LIGHTS_PER_CLUSTER;
    }
    st.shadow = ShadowModule{};
    st.cluster = ClusterModule{};
    st.skybox = SkyboxModule{};
    st.forward = ForwardModule{};
    st.shadow.enabled = if (feature_params) |p| p.enable_shadows != 0 else true;
    const ibl_enabled = if (feature_params) |p| p.enable_ibl != 0 else true;
    st.logger = logger;
    st.bb_writes = .{"backbuffer"};
    st.io = std.mem.zeroes(c.ke_render_pass_io);
    st.io.writes = @ptrCast(&st.bb_writes);
    st.io.writes_count = 1;
    st.io.cmd_slot = 0; // clear pass → frame command slot 0

    const bb_cid = core_h.ref.*.cid.?(core_h.ref, "backbuffer");
    // Zero-size tag for the frame barrier (see ModuleState.frame_cid).
    st.frame_cid = e.component_register.?(e, "render.frame", 0);
    st.begin_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };
    st.clear_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_READ },
    };
    st.end_access = .{
        .{ .cid = bb_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = st.frame_cid, .access = c.KE_ACCESS_WRITE },
    };

    // No pass is imposed. default_passes registers the conventional chain;
    // otherwise the game wires its own passes. A failed setup (e.g. a bad shader)
    // fails loudly via out_error — it is never silently skipped.
    if (default_passes != 0) {
        // Backend clip-space convention — the view stays left-handed (engine
        // world convention); the projection absorbs the z range + Y flip. A
        // right-handed-clip backend is rejected (it would need a right-handed
        // world convention).
        const ndc = dev.get_ndc_convention.?(dev);
        if (ndc.left_handed == 0) {
            c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "render: right-handed clip-space backend not supported (engine world convention is left-handed)", @src().file, @intCast(@src().line), null);
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // Cross-cutting component ids, registered once here (idempotent by name)
        // and handed to each feature module's setup — the modules share cids by
        // name, none owns the registry.
        const mesh_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_MESH, @sizeOf(c.ke_mesh_component));
        const transform_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_TRANSFORM, @sizeOf(c.ke_transform_component));
        const camera_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_CAMERA, @sizeOf(c.ke_camera_component));
        const light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, @sizeOf(c.ke_directional_light_component));
        const point_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(cluster_module.PointLightComp));
        const spot_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(cluster_module.SpotLightComp));
        const ambient_cid = e.component_register.?(e, "AmbientLight", @sizeOf(forward_module.AmbientComp));
        const skybox_cid = e.component_register.?(e, "Skybox", @sizeOf(forward_module.SkyboxComp));

        // Setup order is a real dependency chain, not incidental: shadow +
        // cluster produce the handles forward's set 0/set 3 consume, so they set
        // up first; forward then builds its pipeline (and the set-0 layout the
        // skybox shares), so skybox sets up last against forward.frame_bgl.
        if (!shadow_module.setup(&st.shadow, dev, st.core, ndc, st.shadow.enabled,
                                 mesh_cid, transform_cid, light_cid, st.frame_cid, out_error) or
            !cluster_module.setup(&st.cluster, dev, e, st.core, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
                                  point_light_cid, spot_light_cid, transform_cid, camera_cid, st.frame_cid, out_error) or
            !forward_module.setup(&st.forward, dev, st.core, ndc, logger, ibl_enabled,
                                  mesh_cid, transform_cid, camera_cid, light_cid, point_light_cid, spot_light_cid,
                                  ambient_cid, skybox_cid, st.frame_cid, &st.shadow, &st.cluster, &st.skybox, out_error) or
            !skybox_module.setup(&st.skybox, dev, st.forward.frame_bgl, out_error))
        {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        if (!tonemapSetup(st, out_error)) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // UI overlay pass: loads (doesn't clear) the backbuffer tonemap just wrote,
        // so text/quads composite on top. cmd_slot 5 = after tonemap's slot 4.
        st.ui_writes = .{"backbuffer"};
        st.ui_io = std.mem.zeroes(c.ke_render_pass_io);
        st.ui_io.writes = @ptrCast(&st.ui_writes);
        st.ui_io.writes_count = 1;
        st.ui_io.cmd_slot = 5;
        st.ui_io.load = 1;
        st.ui_access = .{
            .{ .cid = bb_cid, .access = c.KE_ACCESS_WRITE },
        };

        registerSys(rt, "render.begin_frame", null, 0, &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", null, 0, &st.clear_access, st.clear_access.len, st, clearSys);
        if (st.shadow.enabled) {
            registerSys(rt, "render.shadow", null, 0, &st.shadow.access, st.shadow.access.len, &st.shadow, shadow_module.system);
        }
        registerSys(rt, "render.cull", &st.cluster.cull_queries, 3, &st.cluster.cull_access, st.cluster.cull_access.len, &st.cluster, cluster_module.system);
        registerSys(rt, "render.forward", null, 0, &st.forward.fwd_access, st.forward.fwd_access_count, &st.forward, forward_module.system);
        registerSys(rt, "render.tonemap", null, 0, &st.tonemap_access, st.tonemap_access.len, st, tonemapSys);
        registerSys(rt, "render.ui", null, 0, &st.ui_access, st.ui_access.len, st, uiSys);
        registerSys(rt, "render.end_frame", null, 0, &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
