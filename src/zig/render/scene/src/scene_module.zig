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
const abi_part = @import("abi_part");
const part = @import("part");
const abi_render = @import("abi_render");
const abi_render_scene_factory = @import("abi_render_scene_factory");
const abi_render_ui_factory = @import("abi_render_ui_factory");
const abi_render_ui = @import("abi_render_ui");
const abi_result = @import("abi_result");
const abi_settings = @import("abi_settings");
const settings_schema = @import("settings_schema");
const abi_schedule = @import("abi_schedule");
const hooked_systems = @import("hooked_systems");
const abi_extraction = @import("abi_extraction");
const abi_spatial = @import("abi_spatial");
const R = @import("result").Result(.{});
const mesh_resolve = @import("mesh_resolve.zig");
const sprite_resolve = @import("sprite_resolve.zig");
const label_resolve = @import("label_resolve.zig");

const heap = @import("heap");
const gpa = heap.gpa;

/// The state of one scene resolve. The factory allocates it and `destroyScene` frees it. The
/// schedule receives the core and `sprite` as the contexts of its two systems, and their queries
/// point into it, so it is not moved after creation. `destroyScene` unregisters the systems before
/// it frees the resolve.
const SceneResolve = struct {
    api: abi_render.c.ke_render_scene_resolve,
    core: *abi_render.c.ke_render_service,
    systems: hooked_systems.Systems(2) = .{},
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
    st.systems.unregister();
    gpa.destroy(st);
}

/// Registers a component of the contract by its description and returns the id the ecs gives it.
fn registerComponent(e: *abi_ecs.c.ke_ecs, desc: *const abi_ecs.c.ke_component_desc) R.Error!abi_ecs.c.ke_component_id {
    var cid: abi_ecs.c.ke_component_id = abi_ecs.c.KE_COMPONENT_INVALID;
    try R.check(e.component_register.?(e, desc, &cid));
    return cid;
}

fn registerIds(e: *abi_ecs.c.ke_ecs, ids: *abi_render.c.ke_render_scene_component_ids) R.Error!void {
    ids.mesh = try registerComponent(e, &abi_render_contract.c.ke_mesh_component_desc);
    ids.world_transform = try registerComponent(e, &abi_spatial_contract.c.ke_world_transform_component_desc);
    ids.camera = try registerComponent(e, &abi_render_contract.c.ke_camera_component_desc);
    ids.directional_light = try registerComponent(e, &abi_render_contract.c.ke_directional_light_component_desc);
    ids.point_light = try registerComponent(e, &abi_render_contract.c.ke_point_light_component_desc);
    ids.spot_light = try registerComponent(e, &abi_render_contract.c.ke_spot_light_component_desc);
    ids.ambient_light = try registerComponent(e, &abi_render_contract.c.ke_ambient_light_component_desc);
    ids.skybox = try registerComponent(e, &abi_render_contract.c.ke_skybox_component_desc);
    ids.sprite2d = try registerComponent(e, &abi_render_contract.c.ke_sprite2d_component_desc);
    ids.label = try registerComponent(e, &abi_render_contract.c.ke_label_component_desc);
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
export fn ke_render_scene_resolve_create(main_in: ?*abi_ecs.c.ke_ecs, render_in: ?*abi_ecs.c.ke_ecs, extraction_in: ?*abi_extraction.c.ke_extraction, service: ?*abi_render.c.ke_render_service, assets: ?*abi_render.c.ke_render_assets, out_resolve: ?*abi_render.c.ke_render_scene_resolve_handle) callconv(.c) abi_result.c.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const main = main_in orelse return R.code(error.InvalidArgument);
    const render = render_in orelse return R.code(error.InvalidArgument);
    const extraction = extraction_in orelse return R.code(error.InvalidArgument);
    const core = service orelse return R.code(error.InvalidArgument);

    const st = gpa.create(SceneResolve) catch |err| return R.code(err);
    registerScene(st, assets, main, render, extraction, core) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    out.* = .{ .ref = &st.api, .destroy = destroyScene };
    return R.ok;
}

fn registerScene(st: *SceneResolve, assets: ?*abi_render.c.ke_render_assets, main: *abi_ecs.c.ke_ecs, render: *abi_ecs.c.ke_ecs, extraction: *abi_extraction.c.ke_extraction, core: *abi_render.c.ke_render_service) R.Error!void {
    st.* = .{
        .api = .{ .handle = st, .component_ids = componentIds, .render_component_ids = renderComponentIds },
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
    st.sprite = .{ .core = core, .mesh_cid = st.ids.mesh, .assets = assets };
    st.sprite_terms = .{ .{ .component = st.ids.sprite2d, .access = wr }, .{ .component = st.ids.mesh, .access = wr }, .{ .component = st.ids.sprite2d, .access = wr } };
    st.sprite_queries = .{ .{ .terms = st.sprite_terms[0..].ptr, .term_count = 2 }, .{ .terms = st.sprite_terms[2..].ptr, .term_count = 1 } };
    st.mesh_terms = .{.{ .component = st.ids.mesh, .access = wr }};
    st.mesh_queries = .{.{ .terms = st.mesh_terms[0..].ptr, .term_count = 1 }};
}

/// The `destroy` of the owner `ke_render_scene_resolve_systems_create` hands out: unregisters both systems; the
/// resolve stays.
fn destroySceneSystems(ref: ?*anyopaque) callconv(.c) void {
    const st: *SceneResolve = @ptrCast(@alignCast(ref orelse return));
    st.systems.unregister();
}

/// The factory declared in scene_resolve_systems_create.h: registers "render.sprite2d.resolve" in the update hook
/// and "render.mesh.resolve" in the post-update hook, so the mesh a sprite was given is resolved in the same tick;
/// the first is removed when the second is refused. A resolve whose systems are registered refuses another
/// registration as not supported.
export fn ke_render_scene_resolve_systems_create(
    scene: ?*abi_render.c.ke_render_scene_resolve,
    update: ?*abi_schedule.c.ke_schedule,
    update_set: abi_schedule.c.ke_schedule_set_id,
    post_update: ?*abi_schedule.c.ke_schedule,
    post_update_set: abi_schedule.c.ke_schedule_set_id,
    out_systems: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_systems orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const st = sceneOf(scene) orelse return R.code(error.InvalidArgument);
    if (st.systems.schedules[0] != null) return R.code(error.NotSupported);
    const registered = st.systems.register(.{
        .{ .name = "render.sprite2d.resolve", .execute = sprite_resolve.system, .user = &st.sprite, .hook = 0, .queries = &st.sprite_queries },
        .{ .name = "render.mesh.resolve", .execute = mesh_resolve.system, .user = st.core, .hook = 1, .queries = &st.mesh_queries },
    }, &.{ .{ .schedule = update, .set = update_set }, .{ .schedule = post_update, .set = post_update_set } });
    if (registered != R.ok) return registered;
    out.* = .{ .ref = st, .destroy = destroySceneSystems };
    return R.ok;
}

/// The state of one label resolve. The factory allocates it and `destroyLabel` frees it. The schedule receives
/// `state` as the context of the system, and its query points into it, so it is not moved after creation.
const LabelResolve = struct {
    state: label_resolve.State,
    schedule: *abi_schedule.c.ke_schedule,
    system: abi_schedule.c.ke_schedule_system_id = 0,
    set: [1]abi_schedule.c.ke_schedule_set_id,
    terms: [1]abi_ecs.c.ke_ecs_query_term,
    queries: [1]abi_ecs.c.ke_ecs_query_desc,
};

/// The `destroy` of the owner `ke_render_label_resolve_create` hands out: unregisters the system and frees the
/// resolve; a null argument is ignored.
fn destroyLabel(ref: ?*anyopaque) callconv(.c) void {
    const st: *LabelResolve = @ptrCast(@alignCast(ref orelse return));
    _ = st.schedule.unregister_system.?(st.schedule, st.system);
    freeLabel(st);
}

fn freeLabel(st: *LabelResolve) void {
    if (st.state.default_font) |d| gpa.free(d);
    gpa.destroy(st);
}

/// The label resolve's settings, with this implementation's defaults: the font a label that names
/// none draws with, empty for none.
const LabelSettings = struct {
    default_font: [:0]const u8 = "",
};

/// The factory declared in label_resolve_create.h. A missing service, scene, ui, update schedule or settings,
/// or a setting the schema refuses, fails as an invalid argument, a failed allocation as out of memory, and a
/// refused system with the schedule's code.
export fn ke_render_label_resolve_create(
    service_in: ?*abi_render.c.ke_render_service,
    scene_in: ?*abi_render.c.ke_render_scene_resolve,
    ui_in: ?*abi_render_ui.c.ke_render_ui,
    resolver: ?*abi_asset_resolver.c.ke_asset_resolver,
    update_in: ?*abi_schedule.c.ke_schedule,
    update_set: abi_schedule.c.ke_schedule_set_id,
    settings: ?*abi_settings.c.ke_settings,
    out_resolve: ?*abi_part.c.ke_owner,
) callconv(.c) abi_result.c.ke_result {
    const out = out_resolve orelse return R.code(error.InvalidArgument);
    out.* = .{ .ref = null, .destroy = null };
    const core = service_in orelse return R.code(error.InvalidArgument);
    const scene = scene_in orelse return R.code(error.InvalidArgument);
    const ui = ui_in orelse return R.code(error.InvalidArgument);
    const update = update_in orelse return R.code(error.InvalidArgument);
    const values = settings_schema.read(LabelSettings, settings orelse return R.code(error.InvalidArgument)) catch |err| return R.code(err);

    const st = gpa.create(LabelResolve) catch |err| return R.code(err);
    st.* = .{
        .state = .{ .core = core, .ui = ui, .resolver = resolver },
        .schedule = update,
        .set = .{update_set},
        .terms = .{.{ .component = scene.component_ids.?(scene).?.*.label, .access = abi_ecs.c.KE_ECS_ACCESS_WRITE }},
        .queries = undefined,
    };
    st.queries = .{.{ .terms = st.terms[0..].ptr, .term_count = 1 }};
    if (values.default_font.len > 0) st.state.default_font = gpa.dupeZ(u8, values.default_font) catch |err| {
        gpa.destroy(st);
        return R.code(err);
    };
    const label: abi_schedule.c.ke_schedule_system_desc = .{
        .name = "render.label.resolve",
        .user_data = &st.state,
        .execute = label_resolve.system,
        .queries = &st.queries,
        .query_count = st.queries.len,
        .sets = &st.set,
        .set_count = 1,
    };
    const registered = update.register_system.?(update, &label, &st.system);
    if (registered != R.ok) {
        freeLabel(st);
        return registered;
    }
    out.* = .{ .ref = st, .destroy = destroyLabel };
    return R.ok;
}

pub const parts = [_]abi_part.c.ke_part{
    part.of(ke_render_scene_resolve_create, .{ .name = "render_scene_resolve", .slots = &.{"main", "render", "extraction", "service", "assets"}, .optional = &.{"assets"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_scene").setLogCallback) }),
    part.of(ke_render_scene_resolve_systems_create, .{ .name = "render_scene_resolve_systems", .slots = &.{"scene"}, .hooks = &.{"update", "post_update"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_scene").setLogCallback) }),
    part.of(ke_render_label_resolve_create, .{ .name = "render_label_resolve", .slots = &.{"service", "scene", "ui", "resolver"}, .hooks = &.{"update"}, .optional = &.{"resolver"}, .set_log = @ptrCast(&@import("log").Destination("ke_render_scene").setLogCallback) }),
};

/// The library's parts.
export fn ke_render_scene_parts(out_count: ?*usize) callconv(.c) ?*const abi_part.c.ke_part {
    if (out_count) |n| n.* = parts.len;
    return &parts[0];
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

    fn systems(self: *Rig, h: abi_render.c.ke_render_scene_resolve_handle, out: *abi_part.c.ke_owner) abi_result.c.ke_result {
        return ke_render_scene_resolve_systems_create(h.ref, self.schedule.api(), 4, self.schedule.api(), 5, out);
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

test "the scene's systems join the update and post-update hooks and leave with their owner" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    const h = rig.scene();
    defer h.destroy.?(h.ref);
    var m: abi_part.c.ke_owner = undefined;
    try R.check(rig.systems(h, &m));
    try rig.schedule.received(.register_system).times(2);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).sameAs(rig.schedule.received(.register_system));
}

test "scene systems whose mesh system the schedule refuses remove the sprite system and fail" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    _ = rig.schedule.when(.register_system).returnsSeq(&.{ abi_result.c.KE_OK, abi_result.c.KE_RESULT_OUT_OF_MEMORY });
    const h = rig.scene();
    defer h.destroy.?(h.ref);
    var m: abi_part.c.ke_owner = undefined;
    try testing.expect(rig.systems(h, &m) != R.ok);
    try testing.expect(m.ref == null);
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

test "the label resolve registers its system in its update hook, and destroying it unregisters it" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var ui = std.mem.zeroes(abi_render_ui.c.ke_render_ui);
    var m: abi_part.c.ke_owner = undefined;
    try R.check(ke_render_label_resolve_create(rig.core.api(), &test_scene, &ui, null, rig.schedule.api(), 4, &default_font.api, &m));
    try rig.schedule.received(.register_system).times(1);
    m.destroy.?(m.ref);
    try rig.schedule.received(.unregister_system).times(1);
}

test "a label resolve missing its ui is refused as an invalid argument" {
    var rig: Rig = undefined;
    try rig.init();
    defer rig.deinit();
    var m: abi_part.c.ke_owner = undefined;
    try testing.expectError(error.InvalidArgument, R.check(ke_render_label_resolve_create(rig.core.api(), &test_scene, null, null, rig.schedule.api(), 4, &default_font.api, &m)));
    try testing.expect(m.ref == null);
}

test "creating and destroying the scene resolve and the label resolve leaves no block allocated" {
    try heap.expectNoLeaks();
}

test "the library's parts name render_scene_resolve, render_scene_resolve_systems, render_label_resolve and their slots" {
    var count: usize = 0;
    const all = ke_render_scene_parts(&count).?;
    try std.testing.expectEqual(@as(usize, 3), count);
    try std.testing.expectEqualStrings("render_scene_resolve", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[0].name.?));
    try std.testing.expectEqual(@as(usize, 5), @as([*]const abi_part.c.ke_part, @ptrCast(all))[0].slot_count);
    try std.testing.expectEqualStrings("render_scene_resolve_systems", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[1].name.?));
    try std.testing.expectEqual(@as(usize, 3), @as([*]const abi_part.c.ke_part, @ptrCast(all))[1].slot_count);
    try std.testing.expectEqualStrings("render_label_resolve", std.mem.span(@as([*]const abi_part.c.ke_part, @ptrCast(all))[2].name.?));
    try std.testing.expectEqual(@as(usize, 5), @as([*]const abi_part.c.ke_part, @ptrCast(all))[2].slot_count);
}
