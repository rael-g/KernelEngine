//! The shadow pass: the render-phase system "render.shadow" that draws the meshes of the scene into
//! a depth map seen from the directional light, and publishes the light matrix. It also owns the
//! creation and teardown of that pass, behind the one factory it exports.

const std = @import("std");

pub const std_options: std.Options = .{ .signal_stack_size = null };
const zm = @import("zmath");
const cimport = @import("cimport.zig");
const c = cimport.c;

const heap = @import("heap");
const gpa = heap.gpa;


const default_params = c.ke_render_shadow_params{
    .resolution = 1024,
    .light_distance = 25.0,
    .extent = 20.0,
    .near_plane = 0.1,
    .far_plane = 50.0,
};

/// Called by `setup` before anything is created, so the rest of the module only sees the
/// resolved parameters.
fn paramsOr(params: [*c]const c.ke_render_shadow_params) c.ke_render_shadow_params {
    const p = params orelse return default_params;
    return .{
        .resolution = if (p.*.resolution != 0) p.*.resolution else default_params.resolution,
        .light_distance = if (p.*.light_distance != 0.0) p.*.light_distance else default_params.light_distance,
        .extent = if (p.*.extent != 0.0) p.*.extent else default_params.extent,
        .near_plane = if (p.*.near_plane != 0.0) p.*.near_plane else default_params.near_plane,
        .far_plane = if (p.*.far_plane != 0.0) p.*.far_plane else default_params.far_plane,
    };
}

const ShadowObj = extern struct { model: [16]f32 };

const Objects = @import("object_uniforms").ObjectUniforms(c, ShadowObj);

const object_hint = [_]c.ke_render_binding_hint{.{ .name = "object", .flags = c.KE_RENDER_BINDING_HINT_DYNAMIC_OFFSET }};

const shader_layout = c.ke_render_shader_layout_params{
    .shader = "shadow",
    .stages = c.KE_GPU_SHADER_STAGE_VERTEX | c.KE_GPU_SHADER_STAGE_FRAGMENT,
    .hints = &object_hint,
    .hint_count = object_hint.len,
};

/// The state of one shadow pass, allocated by `ke_render_shadow_create` and freed by
/// `destroyHandle`. The registered system keeps a pointer to it as user data from registration on.
/// Fields that `setup` has not reached keep their initial values, so `destroyModule` releases only
/// what exists. `view` is set only when the pass is enabled.
const ShadowModule = struct {
    enabled: bool = false,

    core: *c.ke_render_service = undefined,
    device: *c.ke_gpu_device = undefined,
    ndc: c.ke_ndc_convention = undefined,
    view_space: *c.ke_view_space = undefined,
    params: c.ke_render_shadow_params = default_params,
    mesh_cid: c.ke_component_id = undefined,
    world_transform_cid: c.ke_component_id = undefined,
    light_cid: c.ke_component_id = undefined,
    frame_cid: c.ke_component_id = undefined,

    view: c.ke_gpu_texture_view = c.KE_GPU_INVALID_HANDLE,
    pipeline_params: c.ke_gpu_render_pipeline_params = undefined,
    lvp_uniform: c.ke_gpu_buffer = c.KE_GPU_INVALID_HANDLE,
    binder: *c.ke_render_resource_binder = undefined,
    layout: c.ke_render_shader_layout = c.KE_RENDER_BINDING_INVALID,
    light_set: c.ke_render_resource_set = c.KE_RENDER_BINDING_INVALID,
    objects: ?Objects = null,

    writes: [2][*c]const u8 = undefined,
    io: c.ke_render_pass_io = undefined,
    access: [6]c.ke_component_access = undefined,
    queries_terms: [3]c.ke_component_access = undefined,
    queries: [2]c.ke_query_decl = undefined,
};

/// Called by `system` each tick with the direction it read from the directional light. The result
/// is the matrix uploaded to the light uniform, which is bound to group 0 for the pass.
fn lightViewProj(vs: *c.ke_view_space, ndc: c.ke_ndc_convention, p: c.ke_render_shadow_params, ldir_in: zm.Vec) zm.Mat {
    const ldir = zm.normalize3(ldir_in);
    const eye3 = ldir * zm.f32x4s(-p.light_distance);
    const eye = c.ke_vec3{ .x = eye3[0], .y = eye3[1], .z = eye3[2] };
    const origin = c.ke_vec3{ .x = 0, .y = 0, .z = 0 };
    const up = if (@abs(ldir[1]) > 0.99)
        c.ke_vec3{ .x = 0, .y = 0, .z = 1 }
    else
        c.ke_vec3{ .x = 0, .y = 1, .z = 0 };

    var view: c.ke_mat4 = undefined;
    vs.look_at.?(vs, &eye, &origin, &up, &view);
    var proj: c.ke_mat4 = undefined;
    vs.orthographic.?(vs, p.extent, p.extent, p.near_plane, p.far_plane, &ndc, &proj);
    return zm.mul(zm.loadMat(&view.m), zm.loadMat(&proj.m));
}

/// Reads the first row of the light query, which the draw uses as the direction the light shines;
/// null when the query has no row.
fn lightDirOf(ctx: ?*c.ke_system_ctx) ?zm.Vec {
    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 0, &segc);
    if (segc == 0 or segs[0].count == 0) return null;
    const dl: *const c.ke_directional_light_component = @ptrCast(@alignCast(segs[0].columns[0]));
    return zm.f32x4(dl.direction.x, dl.direction.y, dl.direction.z, 0.0);
}

inline fn moduleOf(user: ?*anyopaque) *ShadowModule {
    return @alignCast(@ptrCast(user.?));
}

/// The render-phase body that `setup` registers as "render.shadow". It returns true on every path,
/// including the early exits for a missing light or a pass that cannot begin, and it ignores its
/// error parameter. It uploads an orthographic light view-projection built from the light's
/// direction to the buffer published as "shadow_lvp", then draws every mesh with a world
/// transform into the "shadow_map" target, "shadow_depth" being its depth attachment. Each mesh
/// gets its own slot of the object uniform and is drawn at that slot's dynamic offset, until the
/// draw cap is reached.
fn system(ctx: ?*c.ke_system_ctx, user: ?*anyopaque, _: f32, out_error: [*c][*c]c.ke_error) callconv(.c) bool {
    const sh = moduleOf(user);
    const core = sh.core;

    const light_dir = lightDirOf(ctx) orelse return true;

    const lvp = lightViewProj(sh.view_space, sh.ndc, sh.params, light_dir);
    var lvp_arr: [16]f32 = undefined;
    zm.storeMat(lvp_arr[0..], lvp);
    core.*.upload.?(core, sh.lvp_uniform, 0, &lvp_arr, 64);

    const pc = core.*.begin_pass.?(core, &sh.io);
    if (pc == null) return true;

    var segc: usize = 0;
    const segs = ctx.?.view.?(ctx, 1, &segc);
    var mesh_total: usize = 0;
    for (segs[0..segc]) |seg| mesh_total += seg.count;
    const objects = &sh.objects.?;
    if (!objects.ensure(@intCast(mesh_total), out_error)) {
        core.*.end_pass.?(core, pc);
        return false;
    }

    const rp = pc.*.begin_render.?(pc);
    rp.*.set_pipeline.?(rp, core.*.get_or_create_pipeline.?(core, &sh.pipeline_params));
    sh.binder.bind_render_set.?(sh.binder, rp, sh.light_set, null, 0);

    var draw_idx: u32 = 0;
    var s: usize = 0;
    while (s < segc) : (s += 1) {
        const meshes: [*c]const c.ke_mesh_component = @ptrCast(@alignCast(segs[s].columns[0]));
        const wts: [*c]const c.ke_world_transform_component = @ptrCast(@alignCast(segs[s].columns[1]));
        var i: usize = 0;
        while (i < segs[s].count) : (i += 1) {
            var vbo: c.ke_gpu_buffer = 0;
            var ibo: c.ke_gpu_buffer = 0;
            var idx_count: u32 = 0;
            if (!core.*.mesh_buffers.?(core, meshes[i].mesh, &vbo, &ibo, &idx_count)) continue;

            var u: ShadowObj = undefined;
            @memcpy(u.model[0..], wts[i].matrix.m[0..16]);
            const offset: u32 = Objects.offset(draw_idx);
            core.*.upload.?(core, objects.buffer, offset, &u, @sizeOf(ShadowObj));

            objects.bind(rp, draw_idx);
            rp.*.set_vertex_buffer.?(rp, 0, vbo, 0);
            rp.*.set_index_buffer.?(rp, ibo, c.KE_GPU_INDEX_FORMAT_UINT16, 0);
            rp.*.draw_indexed.?(rp, idx_count, 1, 0, 0, 0);
            draw_idx += 1;
        }
    }
    rp.*.end.?(rp);
    core.*.end_pass.?(core, pc);
    return true;
}

/// Called once by `ke_render_shadow_create`. It resolves the parameters and creates the light
/// uniform, then stops there when the pass is disabled. An enabled pass also declares its
/// targets, loads the shaders, builds the pipeline, bind groups and per object uniform, and
/// fills the access list and the queries. A step that fails returns false and leaves the handles
/// created before it stored in the module, for `destroyModule` to release. Failures that the render
/// service and the device report go into out_error through those calls; a pipeline that cannot be
/// created is reported as `KE_ERROR_NOT_INITIALIZED`.
fn setup(sh: *ShadowModule, dev: *c.ke_gpu_device, core: *c.ke_render_service,
         ndc: c.ke_ndc_convention, view_space: *c.ke_view_space, enabled: bool, mesh_cid: c.ke_component_id,
         world_transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
         frame_cid: c.ke_component_id, params: [*c]const c.ke_render_shadow_params,
         out_error: [*c][*c]c.ke_error) bool {
    sh.enabled = enabled;
    sh.core = core;
    sh.device = dev;
    sh.ndc = ndc;
    sh.view_space = view_space;
    sh.params = paramsOr(params);
    sh.mesh_cid = mesh_cid;
    sh.world_transform_cid = world_transform_cid;
    sh.light_cid = light_cid;
    sh.frame_cid = frame_cid;

    sh.lvp_uniform = dev.create_buffer.?(dev, &c.ke_gpu_buffer_params{ .label = "shadow.lvp_uniform", .initial_data = null, .size = 64, .usage = c.KE_GPU_BUFFER_USAGE_UNIFORM | c.KE_GPU_BUFFER_USAGE_COPY_DST, .mapped_at_creation = false }, out_error);
    if (sh.lvp_uniform == c.KE_GPU_INVALID_HANDLE) return false;
    _ = core.*.import_buffer.?(core, "shadow_lvp", sh.lvp_uniform, 64, null);

    if (!enabled) return true;

    const shadow_map_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "shadow_map",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = sh.params.resolution,
        .height = sh.params.resolution,
        .scale_x = 1.0,
        .scale_y = 1.0,
        .clear_value = .{ 1.0, 1.0, 1.0, 1.0 },
    }, null);
    const shadow_depth_cid = core.*.declare.?(core, &c.ke_render_resource_params{
        .name = "shadow_depth",
        .type = c.KE_RENDER_RESOURCE_TEXTURE,
        .format = c.KE_GPU_TEXTURE_FORMAT_D32_FLOAT,
        .size_mode = c.KE_RENDER_SIZE_ABSOLUTE,
        .width = sh.params.resolution,
        .height = sh.params.resolution,
        .scale_x = 1.0,
        .scale_y = 1.0,
    }, null);
    sh.view = core.*.resource_view.?(core, "shadow_map");

    const sh_vs = core.*.load_shader.?(core, "shadow", c.KE_GPU_SHADER_STAGE_VERTEX, out_error);
    if (sh_vs == c.KE_GPU_INVALID_HANDLE) return false;
    const sh_fs = core.*.load_shader.?(core, "shadow", c.KE_GPU_SHADER_STAGE_FRAGMENT, out_error);
    if (sh_fs == c.KE_GPU_INVALID_HANDLE) return false;

    sh.binder = core.*.resource_binder.?(core);
    sh.layout = sh.binder.create_shader_layout.?(sh.binder, &shader_layout, out_error);
    if (sh.layout == c.KE_RENDER_BINDING_INVALID) return false;

    const sh_attr = c.ke_gpu_vertex_attribute{ .shader_location = 0, .format = c.KE_GPU_VERTEX_FORMAT_FLOAT32X3, .offset = 0 };
    const sh_vbl = c.ke_gpu_vertex_buffer_layout{ .stride = 11 * @sizeOf(f32), .step_mode = c.KE_GPU_VERTEX_STEP_MODE_VERTEX, .attribute_count = 1, .attributes = &sh_attr };
    var shp = std.mem.zeroes(c.ke_gpu_render_pipeline_params);
    shp.label = "shadow.pipeline";
    shp.vertex_module = sh_vs;
    shp.fragment_module = sh_fs;
    shp.vertex_entry = "vs_main";
    shp.fragment_entry = "fs_main";
    shp.primitive_topology = c.KE_GPU_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    shp.cull_mode = c.KE_GPU_CULL_MODE_NONE;
    shp.front_face = c.KE_GPU_FRONT_FACE_CCW;
    shp.vertex_buffer_count = 1;
    shp.vertex_buffers = &sh_vbl;
    shp.blend_state.write_mask = 0x0F;
    shp.depth_stencil.depth_test_enabled = true;
    shp.depth_stencil.depth_write_enabled = true;
    shp.depth_stencil.depth_compare = c.KE_GPU_COMPARE_LESS;
    if (!sh.binder.pipeline_layouts.?(sh.binder, sh.layout, &shp.bind_group_layouts, shp.bind_group_layouts.len, &shp.bind_group_layout_count, out_error)) return false;
    shp.color_target_formats[0] = c.KE_GPU_TEXTURE_FORMAT_RGBA16_FLOAT;
    shp.color_target_count = 1;
    sh.pipeline_params = shp;
    if (core.*.get_or_create_pipeline.?(core, &sh.pipeline_params) == c.KE_GPU_INVALID_HANDLE) {
        c.ke_error_set(out_error, &c.KE_ERROR_NOT_INITIALIZED, "shadow pass: render pipeline creation failed", @src().file, @intCast(@src().line), null);
        return false;
    }

    const light_binding = [_]c.ke_render_shader_binding{
        .{ .name = "light", .buffer = sh.lvp_uniform, .buffer_offset = 0, .buffer_size = 64, .texture_view = 0, .sampler = 0 },
    };
    sh.light_set = sh.binder.create_set.?(sh.binder, sh.layout, null, "shadow.light_set", &light_binding, light_binding.len, out_error);
    if (sh.light_set == c.KE_RENDER_BINDING_INVALID) return false;

    sh.objects = .{ .device = dev, .binder = sh.binder, .layout = sh.layout, .buffer_label = "shadow.obj_uniform", .set_label = "shadow.obj_set" };
    if (!sh.objects.?.ensure(1, out_error)) return false;

    sh.writes = .{ "shadow_map", "shadow_depth" };
    sh.io = std.mem.zeroes(c.ke_render_pass_io);
    sh.io.name = "render.shadow";
    sh.io.writes = @ptrCast(&sh.writes);
    sh.io.writes_count = 2;
    sh.access = .{
        .{ .cid = shadow_map_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = shadow_depth_cid, .access = c.KE_ACCESS_WRITE },
        .{ .cid = mesh_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = world_transform_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = light_cid, .access = c.KE_ACCESS_READ },
        .{ .cid = frame_cid, .access = c.KE_ACCESS_READ },
    };

    const rd = c.KE_ACCESS_READ;
    sh.queries_terms = .{ .{ .cid = light_cid, .access = rd }, .{ .cid = mesh_cid, .access = rd }, .{ .cid = world_transform_cid, .access = rd } };
    sh.queries = .{ .{ .terms = &sh.queries_terms[0], .term_count = 1 }, .{ .terms = &sh.queries_terms[1], .term_count = 2 } };
    return true;
}

/// Called after a failed `setup` and by `destroyHandle`. It releases only the GPU objects that were
/// created, and leaves freeing the module to its caller.
fn destroyModule(sh: *ShadowModule) void {
    const dev = sh.device;
    if (sh.objects) |*objects| objects.release();
    if (sh.lvp_uniform != c.KE_GPU_INVALID_HANDLE) dev.destroy_buffer.?(dev, sh.lvp_uniform);
    if (sh.layout == c.KE_RENDER_BINDING_INVALID) return;
    sh.binder.destroy_set.?(sh.binder, sh.light_set);
    sh.binder.destroy_shader_layout.?(sh.binder, sh.layout);
}

/// The `destroy` slot of the handle `ke_render_shadow_create` returns. It is the only path that
/// frees a module whose creation succeeded.
fn destroyHandle(self: ?*c.ke_render_shadow) callconv(.c) void {
    const sh: *ShadowModule = @ptrCast(@alignCast(self orelse return));
    destroyModule(sh);
    gpa.destroy(sh);
}

/// Returns an empty handle when a required pointer is null, the allocation fails, `setup` fails or
/// the runtime refuses the system, and every such path frees the module. Failures that the service,
/// the device or the runtime report are left in out_error. The system is registered only when the
/// enabled argument is set; the light uniform is created either way and the handle owns it.
export fn ke_render_shadow_create(runtime: ?*c.ke_runtime, core: ?*c.ke_render_service,
                                   device: ?*c.ke_gpu_device, ndc: c.ke_ndc_convention, view_space: ?*c.ke_view_space,
                                   enabled: bool, mesh_cid: c.ke_component_id,
                                   world_transform_cid: c.ke_component_id, light_cid: c.ke_component_id,
                                   frame_cid: c.ke_component_id,
                                   params: [*c]const c.ke_render_shadow_params,
                                   out_error: [*c][*c]c.ke_error) callconv(.c) c.ke_render_shadow_handle {
    const empty = c.ke_render_shadow_handle{ .ref = null, .destroy = null };
    const rt = runtime orelse return empty;
    const core_ref = core orelse return empty;
    const dev = device orelse return empty;
    const vs = view_space orelse return empty;

    const sh = gpa.create(ShadowModule) catch return empty;
    sh.* = .{};
    if (!setup(sh, dev, core_ref, ndc, vs, enabled, mesh_cid, world_transform_cid, light_cid, frame_cid, params, out_error)) {
        destroyModule(sh);
        gpa.destroy(sh);
        return empty;
    }

    if (sh.enabled) {
        var sys_params = std.mem.zeroes(c.ke_runtime_system_params);
        sys_params.name = "render.shadow";
        sys_params.phase = c.KE_PHASE_RENDER;
        sys_params.queries = &sh.queries;
        sys_params.query_count = sh.queries.len;
        sys_params.access_list = &sh.access;
        sys_params.access_count = sh.access.len;
        sys_params.pinned_thread = 0;
        sys_params.user_data = sh;
        sys_params.execute = system;
        if (rt.register_system.?(rt, &sys_params, out_error) == 0) {
            destroyModule(sh);
            gpa.destroy(sh);
            return empty;
        }
    }

    return .{ .ref = @ptrCast(sh), .destroy = destroyHandle };
}

const testing = std.testing;

const Stubs = @import("stubs").Stubs(c);

test "creating and destroying the shadow pass leaves no block allocated and no GPU resource live" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var view_space = std.mem.zeroes(c.ke_view_space);
    const ndc = std.mem.zeroes(c.ke_ndc_convention);
    const h = ke_render_shadow_create(rt.api(), core.api(), dev.api(), ndc, &view_space, true, 1, 2, 3, 4, &default_params, null);
    try testing.expect(h.ref != null);
    h.destroy.?(h.ref);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a shadow pass whose shader fails to load releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    core.shader_loads_fail = true;
    var rt: Stubs.Runtime = undefined;
    rt.init();
    var view_space = std.mem.zeroes(c.ke_view_space);
    const ndc = std.mem.zeroes(c.ke_ndc_convention);
    const h = ke_render_shadow_create(rt.api(), core.api(), dev.api(), ndc, &view_space, true, 1, 2, 3, 4, &default_params, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}

test "a shadow pass the runtime refuses to register releases what it had created" {
    var dev: Stubs.Device = undefined;
    dev.init();
    var core: Stubs.Core = undefined;
    core.init(dev.api());
    var rt: Stubs.Runtime = undefined;
    rt.init();
    rt.limit = 0;
    var view_space = std.mem.zeroes(c.ke_view_space);
    const ndc = std.mem.zeroes(c.ke_ndc_convention);
    const h = ke_render_shadow_create(rt.api(), core.api(), dev.api(), ndc, &view_space, true, 1, 2, 3, 4, &default_params, null);
    try testing.expect(h.ref == null);
    try testing.expectEqual(@as(i64, 0), dev.live);
    try heap.expectNoLeaks();
}
