const std = @import("std");
const cimport = @import("cimport.zig");
// Cluster is its own physical plugin (ke_render_cluster). These two structs
// mirror its own private PointLightComp/SpotLightComp (duplicated rather than
// imported cross-DLL — same decoupling precedent as forward_common.slang's
// PerObject being copied per pass): the aggregator only needs their byte size
// to register the ECS components, never their fields.
const PointLightComp = extern struct {
    color: [3]f32,
    intensity: f32,
    radius: f32,
};
const SpotLightComp = extern struct {
    dir: [3]f32,
    color: [3]f32,
    intensity: f32,
    range: f32,
    inner_deg: f32,
    outer_deg: f32,
};
// Forward is its own physical plugin (ke_render_forward). These two structs
// mirror its own private AmbientComp/SkyboxComp (duplicated rather than
// imported cross-DLL — same decoupling precedent as PointLightComp/
// SpotLightComp above): the aggregator only needs their byte size to
// register the ECS components, never their fields.
const AmbientComp = extern struct { color: [3]f32 };
const SkyboxComp = extern struct { cubemap: c.ke_texture_handle };

// Compiled into the ke_render_core library (folded here because a separate Zig
// DLL cannot link another Zig DLL's import lib on Windows). Calls the render
// core factory in-lib; the device is caller-created and borrowed. Shared with
// shadow_module.zig via cimport.zig — a second @cImport of the same headers
// would produce distinct, incompatible types for the same C struct.
pub const c = cimport.c;

const gpa = std.heap.c_allocator;

const ExecFn = ?*const fn (?*c.ke_system_ctx, ?*anyopaque, f32) callconv(.c) void;

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
    // and shaders, in its own file. Set up in dependency order: shadow + cluster
    // produce handles gbuffer/deferred/forward consume; gbuffer encodes the
    // opaque G-buffer; deferred-lighting shades it (borrowing shadow/cluster +
    // tracking the env cubemap for IBL); skybox fills the pixels neither wrote;
    // forward shades the transparent (BLEND) surfaces gbuffer skipped, sharing
    // deferred's shadow/cluster/IBL wiring plus its own refraction snapshot.
    // This aggregator holds them so their addresses are stable for the
    // borrowed pointers and the systems' user_data.
    // Shadow is its own physical plugin (ke_render_shadow) — this aggregator
    // only holds the borrowed handle it returned, not its private state.
    shadow: c.ke_render_shadow_handle,
    // Cluster is its own physical plugin (ke_render_cluster) — this aggregator
    // only holds the borrowed handle it returned, not its private state.
    cluster: c.ke_render_cluster_handle,
    // Gbuffer encode is its own physical plugin (ke_render_gbuffer) — this
    // aggregator only holds the borrowed handle it returned, not its private state.
    gbuffer: c.ke_render_gbuffer_handle,
    // Deferred lighting is its own physical plugin (ke_render_deferred_lighting)
    // — this aggregator only holds the borrowed handle it returned, not its
    // private state.
    deferred: c.ke_render_deferred_lighting_handle,
    // Skybox is its own physical plugin (ke_render_skybox) — this aggregator
    // only holds the borrowed handle it returned, not its private state.
    skybox: c.ke_render_skybox_handle,
    // Forward is its own physical plugin (ke_render_forward) — this aggregator
    // only holds the borrowed handle it returned, not its private state.
    forward: c.ke_render_forward_handle,
    // Tonemap is its own physical plugin (ke_render_tonemap) — this aggregator
    // only holds the borrowed handle it returned, not its private state.
    tonemap: c.ke_render_tonemap_handle,
    // UI is its own physical plugin (ke_render_ui) — this aggregator only
    // holds the borrowed vtable handle it returned, not its private state.
    ui: c.ke_render_ui_handle,
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

// Queues a screen-space UI quad for this frame — forwarded into the ui plugin's
// own vtable (ke_render_ui.ui_quad), not handled by ke_render_core. Replaces
// the old ke_render_core.ui_quad vtable slot; see ke_render_ui for why it moved.
export fn ke_render_module_ui_quad(module: ?*c.ke_render_module, texture: c.ke_texture_handle,
                                   dst_x: f32, dst_y: f32, dst_w: f32, dst_h: f32,
                                   uv0: f32, uv1: f32, uv2: f32, uv3: f32,
                                   r: f32, g: f32, b: f32, a: f32) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(module orelse return));
    st.ui.ref.*.ui_quad.?(st.ui.ref, texture, dst_x, dst_y, dst_w, dst_h, uv0, uv1, uv2, uv3, r, g, b, a);
}

fn destroyModule(self: ?*c.ke_render_module) callconv(.c) void {
    const st: *ModuleState = @alignCast(@ptrCast(self orelse return));
    if (st.tonemap.destroy) |d| d(st.tonemap.ref);
    if (st.skybox.destroy) |d| d(st.skybox.ref);
    if (st.ui.destroy) |d| d(st.ui.ref);
    if (st.forward.destroy) |d| d(st.forward.ref);
    if (st.deferred.destroy) |d| d(st.deferred.ref);
    if (st.gbuffer.destroy) |d| d(st.gbuffer.ref);
    if (st.shadow.destroy) |d| d(st.shadow.ref);
    if (st.cluster.destroy) |d| d(st.cluster.ref);
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
    // any of these rather than hit a hardcoded ceiling.
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
    st.shadow = .{ .ref = null, .destroy = null };
    st.cluster = .{ .ref = null, .destroy = null };
    st.gbuffer = .{ .ref = null, .destroy = null };
    st.deferred = .{ .ref = null, .destroy = null };
    st.skybox = .{ .ref = null, .destroy = null };
    st.forward = .{ .ref = null, .destroy = null };
    st.tonemap = .{ .ref = null, .destroy = null };
    st.ui = .{ .ref = null, .destroy = null };
    const shadow_enabled = if (feature_params) |p| p.enable_shadows != 0 else true;
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
        const point_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_POINT_LIGHT, @sizeOf(PointLightComp));
        const spot_light_cid = e.component_register.?(e, c.KE_COMPONENT_NAME_SPOT_LIGHT, @sizeOf(SpotLightComp));
        const ambient_cid = e.component_register.?(e, "AmbientLight", @sizeOf(AmbientComp));
        const skybox_cid = e.component_register.?(e, "Skybox", @sizeOf(SkyboxComp));

        // begin_frame/clear are registered first, unconditionally, before any
        // pass's setup runs: gbuffer is its own physical plugin whose create()
        // call both configures it (declaring gbuffer_albedo/normal/emissive —
        // deferred_lighting.setup() below resolves those cids) AND registers
        // its runtime system in the same call. Registering begin_frame/clear
        // up front guarantees they're ahead of gbuffer's system in the wave
        // order regardless of where gbuffer's combined call lands (registration
        // order determines wave placement — see the tonemap/skybox plugins for
        // the same lesson learned the hard way: an out-of-order registration
        // races ahead of begin_frame's per-slot encoder pre-creation).
        registerSys(rt, "render.begin_frame", null, 0, &st.begin_access, st.begin_access.len, st, beginFrameSys);
        registerSys(rt, "render.clear", null, 0, &st.clear_access, st.clear_access.len, st, clearSys);

        // Setup order is a real dependency chain: shadow + cluster publish their
        // outputs (LVP uniform, shadow view, light-list bind group + layout)
        // into the named-resource table first, so gbuffer/deferred/forward can
        // look them up by name — none of them holds a pointer to ShadowModule/
        // ClusterModule. gbuffer encodes; deferred-lighting decodes + shades.
        //
        // Shadow is its own physical plugin: create() both declares its
        // resources ("shadow_map" view, "shadow_lvp" buffer — deferred/forward
        // resolve them by name) and registers its runtime system only when
        // enabled, in the position its old registerSys call used to occupy.
        st.shadow = c.ke_render_shadow_create(rt, st.core.ref, dev, ndc, @intFromBool(shadow_enabled),
                                              mesh_cid, transform_cid, light_cid, st.frame_cid, out_error);
        if (st.shadow.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // Cluster is its own physical plugin: create() both declares its
        // outputs ("cluster_lights" bind group + layout, "light_clusters"
        // ordering tag — deferred/forward resolve them by name) and registers
        // its runtime system, in the position its old registerSys call used
        // to occupy.
        st.cluster = c.ke_render_cluster_create(rt, st.core.ref, dev, logger, grid_x, grid_y, grid_z, max_lights_per_cluster,
                                                point_light_cid, spot_light_cid, transform_cid, camera_cid, st.frame_cid, out_error);
        if (st.cluster.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // Gbuffer is its own physical plugin: create() both declares its
        // resources (gbuffer_albedo/normal/emissive/depth — needed by
        // deferred-lighting's setup below) and registers its runtime system,
        // in the position its old registerSys call used to occupy.
        st.gbuffer = c.ke_render_gbuffer_create(rt, st.core.ref, dev, ndc, mesh_cid, transform_cid, camera_cid, st.frame_cid, out_error);
        if (st.gbuffer.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }

        // Deferred lighting is its own physical plugin: create() both decodes
        // the G-buffer setup (reading shadow/cluster's outputs by name through
        // ke_render_core) and registers its runtime system, in the position
        // its old registerSys call used to occupy.
        st.deferred = c.ke_render_deferred_lighting_create(rt, st.core.ref, dev, ndc, logger, @intFromBool(ibl_enabled),
                                                            camera_cid, transform_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.deferred.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        // Skybox is its own physical plugin: its factory registers its own
        // runtime system directly, matching the position its old registerSys
        // call used to occupy (registration order matters — see tonemap above).
        st.skybox = c.ke_render_skybox_create(rt, st.core.ref, dev, ndc, camera_cid, transform_cid, skybox_cid, st.frame_cid, out_error);
        if (st.skybox.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        // Forward is its own physical plugin: create() both configures the
        // transparent-only pipeline (reading shadow/cluster's outputs by name
        // through ke_render_core, sharing deferred-lighting's shading hooks)
        // and registers its runtime system, in the position its old
        // registerSys call used to occupy.
        st.forward = c.ke_render_forward_create(rt, st.core.ref, dev, ndc, logger, @intFromBool(ibl_enabled),
                                                mesh_cid, transform_cid, camera_cid, light_cid, ambient_cid, skybox_cid, st.frame_cid, out_error);
        if (st.forward.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        // Tonemap is its own physical plugin: its factory registers its own
        // runtime system directly (no registerSys call here, unlike the
        // in-process modules above). Created here — matching the position the
        // in-process module's own registerSys call used to occupy — because
        // registration ORDER (not just declared cid access) affects which wave
        // a tied system lands in; creating it earlier raced it ahead of
        // begin_frame's per-slot encoder pre-creation.
        st.tonemap = c.ke_render_tonemap_create(rt, st.core.ref, dev, logger, out_error);
        if (st.tonemap.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        // UI overlay pass: its own physical plugin, factory registers its own
        // runtime system, matching the position its old registerSys call
        // occupied. cmd_slot 8 = after tonemap's slot 7 (loads, doesn't clear,
        // the backbuffer tonemap just wrote, so text/quads composite on top).
        st.ui = c.ke_render_ui_create(rt, st.core.ref, dev, ndc, bb_cid, 8, out_error);
        if (st.ui.ref == null) {
            if (core_h.destroy) |d| d(core_h.ref);
            gpa.destroy(st);
            return empty;
        }
        registerSys(rt, "render.end_frame", null, 0, &st.end_access, st.end_access.len, st, endFrameSys);
    }

    return .{ .ref = @ptrCast(st), .destroy = destroyModule };
}
