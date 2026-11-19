//! The scene side of render: the scene's components in the main and the render world, paired by the
//! extraction, and the main-world systems that give a mesh, a sprite and a label the GPU resources
//! and the font they name, behind one factory each.

const abi_render_contract = @import("abi_render_contract");
const abi_spatial_contract = @import("abi_spatial_contract");
const abi_asset_resolver = @import("abi_asset_resolver");
const abi_render_components = @import("abi_render_components");
const abi_ui_components = @import("abi_ui_components");
const std = @import("std");
const log = std.log.scoped(.render_scene);

pub const std_options: std.Options = .{ .signal_stack_size = null, .logFn = @import("log").Destination("ke_render_scene").logFn };

pub const abi_ecs = @import("abi_ecs");
const abi_render = @import("abi_render");
const abi_render_context = @import("abi_render_context");
const abi_render_scene_factory = @import("abi_render_scene_factory");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_render_ui = @import("abi_render_ui");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const abi_module = @import("abi_module");
const abi_extraction = @import("abi_extraction");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

const heap = @import("heap");
const gpa = heap.gpa;

/// The state of one scene resolve. The factory allocates it and `destroyScene` frees it. The
/// schedule receives the core and `sprite` as the contexts of the two systems of `module`, and
/// their queries point into it, so it is not moved after creation. `destroyScene` detaches the
/// module before it frees the resolve.
const SceneResolve = struct {
    api: abi_render.c.ke_render_scene_resolve,
    module: abi_module.c.ke_module,
    core: *abi_render.c.ke_render_service,
    schedule: ?*abi_schedule.c.ke_schedule = null,
    systems: [2]abi_schedule.c.ke_schedule_system_id = .{ 0, 0 },
    sets: [2]abi_schedule.c.ke_schedule_set_id = .{ 0, 0 },
    ids: abi_render.c.ke_render_scene_component_ids,
    render_ids: abi_render.c.ke_render_scene_component_ids,
    sprite: sprite_resolve.State,
    mesh_terms: [1]abi_ecs.c.ke_ecs_query_term,
    mesh_queries: [1]abi_ecs.c.ke_ecs_query_desc,
    sprite_terms: [3]abi_ecs.c.ke_ecs_query_term,
    sprite_queries: [2]abi_ecs.c.ke_ecs_query_desc,
};

fn sceneOf(self: ?*abi_render.c.ke_render_scene_resolve) ?*SceneResolve {
    return @ptrCast(@alignCast((self orelse return null).handle));
}

fn sceneOfModule(self: ?*abi_module.c.ke_module) ?*SceneResolve {
    return @ptrCast(@alignCast((self orelse return null).handle));
}

/// The `component_ids` slot.
fn componentIds(self: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &(sceneOf(self) orelse return null).ids;
}

/// The `render_component_ids` slot.
fn renderComponentIds(self: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &(sceneOf(self) orelse return null).render_ids;
}

/// The `destroy` slot of the handle `ke_render_scene_resolve_create` returns; a null argument is
/// ignored.
fn destroyScene(self: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) void {
    const st = sceneOf(self) orelse return;
    detachScene(&st.module);
    gpa.destroy(st);
}

/// Registers the component type with the ecs under its name, its size and its field table, and
/// returns the id the ecs gives it.
fn registerComponent(e: *abi_ecs.c.ke_ecs, name: [*c]const u8, comptime T: type, comptime table: anytype) R.Error!abi_asset_resolver.c.ke_component_id {
    const fields = @typeInfo(@TypeOf(table.*)).array;
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_desc{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = table, .field_count = @intCast(fields.len) }, &cid));
    return cid;
}

fn registerBare(e: *abi_ecs.c.ke_ecs, name: [*c]const u8, comptime T: type) R.Error!abi_asset_resolver.c.ke_component_id {
    var cid: abi_asset_resolver.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, &abi_ecs.c.ke_component_desc{ .name = name, .size = @sizeOf(T), .alignment = @alignOf(T), .fields = null, .field_count = 0 }, &cid));
    return cid;
}

fn registerIds(e: *abi_ecs.c.ke_ecs, ids: *abi_render.c.ke_render_scene_component_ids) R.Error!void {
    ids.mesh = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_MESH, abi_render_components.c.ke_mesh_component, &abi_render_contract.c.ke_mesh_component_fields);
    ids.world_transform = try registerBare(e, abi_spatial_contract.c.KE_COMPONENT_NAME_WORLD_TRANSFORM, abi_spatial.c.ke_world_transform_component);
    ids.camera = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_CAMERA, abi_render_components.c.ke_camera_component, &abi_render_contract.c.ke_camera_component_fields);
    ids.directional_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_DIRECTIONAL_LIGHT, abi_render_components.c.ke_directional_light_component, &abi_render_contract.c.ke_directional_light_component_fields);
    ids.point_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_POINT_LIGHT, abi_render_components.c.ke_point_light_component, &abi_render_contract.c.ke_point_light_component_fields);
    ids.spot_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_SPOT_LIGHT, abi_render_components.c.ke_spot_light_component, &abi_render_contract.c.ke_spot_light_component_fields);
    ids.ambient_light = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_AMBIENT_LIGHT, abi_render_components.c.ke_ambient_light_component, &abi_render_contract.c.ke_ambient_light_component_fields);
    ids.skybox = try registerBare(e, abi_render_contract.c.KE_COMPONENT_NAME_SKYBOX, abi_render_components.c.ke_skybox_component);
    ids.sprite2d = try registerComponent(e, abi_render_contract.c.KE_COMPONENT_NAME_SPRITE2D, abi_render_components.c.ke_sprite2d_component, &abi_render_contract.c.ke_sprite2d_component_fields);
    ids.label = try registerComponent(e, abi_ui_components.c.KE_COMPONENT_NAME_LABEL, abi_ui_components.c.ke_label_component, &abi_render_contract.c.ke_label_component_fields);
}

/// The components every pair of the render world carries when its entity has them, and those whose
/// presence alone gives an entity its pair.
const synced_fields = [_][]const u8{ "mesh", "camera", "directional_light", "point_light", "spot_light", "ambient_light", "skybox", "sprite2d", "label" };

fn pair(extraction: *abi_extraction.c.ke_extraction, ids: *const abi_render.c.ke_render_scene_component_ids, render_ids: *const abi_render.c.ke_render_scene_component_ids) R.Error!void {
    inline for (@typeInfo(abi_render.c.ke_render_scene_component_ids).@"struct".fields) |f| {
        try R.check(extraction.extract_copy.?(extraction, @field(ids, f.name), @field(render_ids, f.name)));
    }
    inline for (synced_fields) |name| try R.check(extraction.sync_component.?(extraction, @field(ids, name)));
}

/// The factory declared in scene_resolve_create.h. A missing world, extraction or service fails as
/// an invalid argument, a failed allocation as out of memory, and a component a world or the
/// extraction refuses with its code; each leaves the handle zeroed.
export fn ke_render_scene_resolve_create(main_in: ?*abi_ecs.c.ke_ecs, render_in: ?*abi_ecs.c.ke_ecs, extraction_in: ?*abi_extraction.c.ke_extraction, service: ?*abi_render.c.ke_render_service, resolver: ?*abi_asset_resolver.c.ke_asset_resolver, out_resolve: ?*abi_render.c.ke_render_scene_resolve_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const main = main_in orelse return R.code(error.InvalidArgument);
    const render = render_in orelse return R.code(error.InvalidArgument);
    const extraction = extraction_in orelse return R.code(error.InvalidArgument);
    const core = service orelse return R.code(error.InvalidArgument);

    const st = gpa.create(SceneResolve) catch |err| return R.code(err);
    registerScene(st, resolver, main, render, extraction, core) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    out.* = .{ .ref = &st.api, .destroy = destroyScene };
    return R.ok;
}

fn registerScene(st: *SceneResolve, resolver: ?*abi_asset_resolver.c.ke_asset_resolver, main: *abi_ecs.c.ke_ecs, render: *abi_ecs.c.ke_ecs, extraction: *abi_extraction.c.ke_extraction, core: *abi_render.c.ke_render_service) R.Error!void {
    st.* = .{
        .api = .{ .handle = st, .component_ids = componentIds, .render_component_ids = renderComponentIds },
        .module = .{ .handle = st, .attach = attachScene, .detach = detachScene },
        .core = core,
        .ids = undefined,
        .render_ids = undefined,
        .sprite = undefined,
        .mesh_terms = undefined,
        .mesh_queries = undefined,
        .sprite_terms = undefined,
        .sprite_queries = undefined,
    };
    try registerIds(main, &st.ids);
    try registerIds(render, &st.render_ids);
    try pair(extraction, &st.ids, &st.render_ids);

    const wr = abi_ecs.c.KE_ECS_ACCESS_WRITE;
    st.sprite = .{ .core = core, .mesh_cid = st.ids.mesh, .resolver = resolver };
    st.sprite_terms = .{ .{ .component = st.ids.sprite2d, .access = wr }, .{ .component = st.ids.mesh, .access = wr }, .{ .component = st.ids.sprite2d, .access = wr } };
    st.sprite_queries = .{ .{ .terms = st.sprite_terms[0..].ptr, .term_count = 2 }, .{ .terms = st.sprite_terms[2..].ptr, .term_count = 1 } };
    st.mesh_terms = .{.{ .component = st.ids.mesh, .access = wr }};
    st.mesh_queries = .{.{ .terms = st.mesh_terms[0..].ptr, .term_count = 1 }};
}

/// Slot `attach` of the scene's module: "render.sprite2d.resolve" in the update set and
/// "render.mesh.resolve" in the post-update set, so the mesh a sprite was given is resolved in the
/// same tick; the first is removed when the second is refused.
fn attachScene(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) abi_result.c.ke_result {
    const st = sceneOfModule(self) orelse return R.code(error.InvalidArgument);
    const targets = targets_in orelse return R.code(error.InvalidArgument);
    if (st.schedule != null) return R.code(error.NotSupported);
    const schedule: *abi_schedule.c.ke_schedule = @ptrCast(targets.update orelse return R.code(error.InvalidArgument));
    st.sets = .{ targets.update_set, targets.post_update_set };
    const sprite: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.sprite2d.resolve",
        .user_data = &st.sprite,
        .execute = sprite_resolve.system,
        .queries = &st.sprite_queries,
        .query_count = st.sprite_queries.len,
        .sets = st.sets[0..].ptr,
        .set_count = 1,
    };
    const registered = schedule.register_system.?(schedule, &sprite, &st.systems[0]);
    if (registered != R.ok) return registered;
    const mesh: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.mesh.resolve",
        .user_data = st.core,
        .execute = mesh_resolve.system,
        .queries = &st.mesh_queries,
        .query_count = st.mesh_queries.len,
        .sets = st.sets[1..].ptr,
        .set_count = 1,
    };
    const meshed = schedule.register_system.?(schedule, &mesh, &st.systems[1]);
    if (meshed != R.ok) {
        _ = schedule.unregister_system.?(schedule, st.systems[0]);
        return meshed;
    }
    st.schedule = schedule;
    return R.ok;
}

/// Slot `detach` of the scene's module.
fn detachScene(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const st = sceneOfModule(self) orelse return;
    const schedule = st.schedule orelse return;
    for (st.systems) |id| _ = schedule.unregister_system.?(schedule, id);
    st.schedule = null;
}

fn destroySceneModule(self: ?*abi_module.c.ke_module) callconv(.c) void {
    detachScene(self);
}

/// The factory declared in scene_resolve_systems_create.h: the module is a view of the resolve,
/// destroyed with it or on its own.
export fn ke_render_scene_resolve_systems_create(scene: ?*abi_render.c.ke_render_scene_resolve, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const st = sceneOf(scene) orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = &st.module, .destroy = destroySceneModule };
    return R.ok;
}

/// The state of one label resolve, which is its own module. The factory allocates it and
/// `destroyLabel` frees it. The schedule receives `state` as the context of the system, and its
/// query points into it, so it is not moved after creation. `destroyLabel` detaches it first.
const LabelResolve = struct {
    module: abi_module.c.ke_module,
    state: label_resolve.State,
    schedule: ?*abi_schedule.c.ke_schedule = null,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    set: [1]abi_schedule.c.ke_schedule_set_id = .{0},
    terms: [1]abi_ecs.c.ke_ecs_query_term,
    queries: [1]abi_ecs.c.ke_ecs_query_desc,
};

fn labelOf(self: ?*abi_module.c.ke_module) ?*LabelResolve {
    return @ptrCast(@alignCast((self orelse return null).handle));
}

/// Slot `attach` of the label resolve: "render.label.resolve" in the update set.
fn attachLabel(self: ?*abi_module.c.ke_module, targets_in: ?*const abi_module.c.ke_module_targets) callconv(.c) abi_result.c.ke_result {
    const st = labelOf(self) orelse return R.code(error.InvalidArgument);
    const targets = targets_in orelse return R.code(error.InvalidArgument);
    if (st.schedule != null) return R.code(error.NotSupported);
    const schedule: *abi_schedule.c.ke_schedule = @ptrCast(targets.update orelse return R.code(error.InvalidArgument));
    st.set = .{targets.update_set};
    const label: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.label.resolve",
        .user_data = &st.state,
        .execute = label_resolve.system,
        .queries = &st.queries,
        .query_count = st.queries.len,
        .sets = &st.set,
        .set_count = 1,
    };
    const registered = schedule.register_system.?(schedule, &label, &st.system);
    if (registered != R.ok) return registered;
    st.schedule = schedule;
    return R.ok;
}

/// Slot `detach` of the label resolve.
fn detachLabel(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const st = labelOf(self) orelse return;
    const schedule = st.schedule orelse return;
    _ = schedule.unregister_system.?(schedule, st.system);
    st.schedule = null;
}

/// The `destroy` slot of the handle `ke_render_label_resolve_create` returns; a null argument is
/// ignored.
fn destroyLabel(self: ?*abi_module.c.ke_module) callconv(.c) void {
    const st = labelOf(self) orelse return;
    detachLabel(self);
    if (st.state.default_font) |d| gpa.free(d);
    gpa.destroy(st);
}

/// The label resolve's settings, with this implementation's defaults: the font a label that names
/// none draws with, empty for none.
const LabelSettings = struct {
    default_font: [:0]const u8 = "",
};

/// The factory declared in label_resolve_create.h. A missing context, scene, service, ui or
/// settings, or a setting the schema refuses, fails as an invalid argument and a failed allocation
/// as out of memory.
export fn ke_render_label_resolve_create(context_in: ?*const abi_render_context.c.ke_render_context, ui_in: ?*abi_render_ui.c.ke_render_ui, resolver: ?*abi_asset_resolver.c.ke_asset_resolver, settings: ?*abi_settings.c.ke_settings, out_module: ?*abi_module.c.ke_module_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_module orelse return R.code(error.InvalidArgument);
    out.* = std.mem.zeroes(abi_module.c.ke_module_handle);
    const p = context_in orelse return R.code(error.InvalidArgument);
    const core = p.service orelse return R.code(error.InvalidArgument);
    const ui = ui_in orelse return R.code(error.InvalidArgument);
    const scene = p.scene orelse return R.code(error.InvalidArgument);
    const values = settings_schema.read(LabelSettings, settings orelse return R.code(error.InvalidArgument)) catch |err| return R.code(err);

    const st = gpa.create(LabelResolve) catch |err| return R.code(err);
    st.* = .{
        .module = .{ .handle = st, .attach = attachLabel, .detach = detachLabel },
        .state = .{ .core = core, .ui = ui, .resolver = resolver },
        .terms = .{.{ .component = scene.component_ids.?(scene).?.*.label, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }},
        .queries = undefined,
    };
    st.queries = .{.{ .terms = st.terms[0..].ptr, .term_count = 1 }};
    if (values.default_font.len > 0) st.state.default_font = gpa.dupeZ(u8, values.default_font) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    out.* = .{ .ref = &st.module, .destroy = destroyLabel };
    return R.ok;
}

const testing = std.testing;
const zsub = @import("zsub");

const test_ids = std.mem.zeroInit(abi_render.c.ke_render_scene_component_ids, .{ .label = 9 });

fn testComponentIds(_: ?*abi_render.c.ke_render_scene_resolve) callconv(.c) ?*const abi_render.c.ke_render_scene_component_ids {
    return &test_ids;
}

var test_scene: abi_render.c.ke_render_scene_resolve = .{ .handle = null, .component_ids = testComponentIds, .render_component_ids = testComponentIds };

const Rig = struct {
    core: zsub.For(abi_render.c.ke_render_service),
    schedule: zsub.For(abi_schedule.c.ke_schedule),
    main: zsub.For(abi_ecs.c.ke_ecs),
    render: zsub.For(abi_ecs.c.ke_ecs),
    extraction: zsub.For(abi_extraction.c.ke_extraction),

    fn init(self: *Rig) !void {
        try self.core.init();
        try self.schedule.init();
        _ = self.schedule.when(.register_system).writesFresh(2);
        try self.main.init();
        _ = self.main.when(.component_register).writesFresh(2);
        try self.render.init();
        _ = self.render.when(.component_register).writesFresh(2);
        try self.extraction.init();
    }

    fn deinit(self: *Rig) void {
        self.extraction.deinit();
        self.render.deinit();
        self.main.deinit();
        self.schedule.deinit();
        self.core.deinit();
    }

    fn scene(self: *Rig) abi_render.c.ke_render_scene_resolve_handle {
        var h: abi_render.c.ke_render_scene_resolve_handle = .{ .ref = null, .destroy = null };
        _ = ke_render_scene_resolve_create(self.main.api(), self.render.api(), self.extraction.api(), self.core.api(), null, &h);
        return h;
    }

    fn targets(self: *Rig) abi_module.c.ke_module_targets {
        var t = std.mem.zeroes(abi_module.c.ke_module_targets);
        t.update = @ptrCast(self.schedule.api());
        return t;
    }
};

const id_count = @typeInfo(abi_render.c.ke_render_scene_component_ids).@"struct".fields.len;

test "the scene resolve registers every component in both worlds, copies each into the render world and syncs the drawable ones" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.scene();
    try testing.expect(h.ref != null);
    defer h.destroy.?(h.ref);
    try rig.main.received(.component_register).times(id_count);
    try rig.render.received(.component_register).times(id_count);
    try rig.extraction.received(.extract_copy).times(id_count);
    try rig.extraction.received(.sync_component).times(synced_fields.len);
    const ids = h.ref.?.component_ids.?(h.ref).?;
    const render_ids = h.ref.?.render_component_ids.?(h.ref).?;
    inline for (@typeInfo(abi_render.c.ke_render_scene_component_ids).@"struct".fields) |f| {
        try testing.expect(@field(ids.*, f.name) != abi_ecs.c.KE_COMPONENT_INVALID);
        try testing.expect(@field(render_ids.*, f.name) != abi_ecs.c.KE_COMPONENT_INVALID);
    }
}

test "the scene's module registers both resolve systems in the update schedule and detaching removes them" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.scene();
    defer h.destroy.?(h.ref);
    var m: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_scene_resolve_systems_create(h.ref, &m));
    const t = rig.targets();
    try R.check(m.ref.?.attach.?(m.ref, &t));
    try rig.schedule.received(.register_system).times(2);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).sameAs(rig.schedule.received(.register_system));
}

test "a scene module whose mesh system the schedule refuses removes its sprite system and fails" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.schedule.when(.register_system).returnsSeq(&.{ abi_result.c.KE_OK, abi_result.c.KE_RESULT_OUT_OF_MEMORY });
    const h = rig.scene();
    defer h.destroy.?(h.ref);
    var m: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_scene_resolve_systems_create(h.ref, &m));
    const t = rig.targets();
    try testing.expect(m.ref.?.attach.?(m.ref, &t) != R.ok);
    try rig.schedule.received(.unregister_system).times(1);
}

test "a scene resolve missing its extraction is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var h: abi_render.c.ke_render_scene_resolve_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_scene_resolve_create(rig.main.api(), rig.render.api(), null, rig.core.api(), null, &h)));
    try testing.expect(h.ref == null);
}

var default_font = settings_schema.Fixed.init(&.{.{ .key = "default_font", .value = .{ .string = "res://default.ttf" } }});

test "the label resolve attaches its system to the update set, and detaching removes it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    const p = std.mem.zeroInit(abi_render_context.c.ke_render_context, .{ .service = rig.core.api(), .scene = &test_scene });
    var m: abi_module.c.ke_module_handle = undefined;
    try R.check(ke_render_label_resolve_create(&p, &ui, null, &default_font.api, &m));
    const t = rig.targets();
    try R.check(m.ref.?.attach.?(m.ref, &t));
    try rig.schedule.received(.register_system).times(1);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).times(1);
}

test "a label resolve missing its ui is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const p = std.mem.zeroInit(abi_render_context.c.ke_render_context, .{ .service = rig.core.api(), .scene = &test_scene });
    var m: abi_module.c.ke_module_handle = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_label_resolve_create(&p, null, null, &default_font.api, &m)));
    try testing.expect(m.ref == null);
}

test "creating and destroying the scene resolve and the label resolve leaves no block allocated" {
    try heap.expectNoLeaks();
}
