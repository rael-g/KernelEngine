-- Pong in Lua over LuaJIT FFI.
-- Everything plumbing (DLL load, allocator, logger, window, render, world,
-- tree, render systems, frame packet) lives in bootstrap.lua. This file owns
-- the scene-specific parts: node-type callbacks for the SceneLoader, the
-- scene file, input actions, the frame loop, and shutdown.

local ffi = require("ffi")

local script_dir = (arg[0] or ""):gsub("[^/\\]+$", "")
if script_dir == "" then script_dir = "." end
local app = dofile(script_dir .. "bootstrap.lua")

local alloc, framework, kernel, render = app.alloc, app.framework, app.kernel, app.render
local world, tree, registry, packet    = app.world, app.tree, app.registry, app.packet
local cam_cid, mesh_cid, dir_cid       = app.cam_cid, app.mesh_cid, app.dir_cid

-- ── Node-type callbacks the SceneLoader will dispatch into ──────────────────
-- One ke_node_type per scene-file `type = "..."`. Each callback closes over
-- the cids + render handle above; we anchor the ffi.cast cdata in a Lua table
-- so it outlives GC for the lifetime of the program.

local nt_anchor = {}
local function cb(sig, fn)
    local c = ffi.cast(sig, fn)
    nt_anchor[#nt_anchor + 1] = c
    return c
end

-- KE_VARIANT_* enum values (see kernel/world/variant.h).
local V_FLOAT, V_STRING, V_VEC3, V_VEC4 = 3, 4, 6, 7
local function as_float(v)
    if v.type == V_FLOAT then return v.f end
    if v.type == 2 then return tonumber(v.i) end -- KE_VARIANT_INT
    return 0.0
end

-- ── DirectionalLight ────────────────────────────────────────────────────────
local dir_create = cb("ke_node_create_func", function(_ctx, entity, _name)
    local c = ffi.cast("ke_directional_light_component*",
        kernel.ke_ecs_component_add(registry, entity, dir_cid))
    c.dir_x, c.dir_y, c.dir_z = 0, -1, 0
    c.r, c.g, c.b = 1, 1, 1
    c.intensity = 1.0
    return 0
end)
local dir_set = cb("ke_node_set_property_func", function(_ctx, entity, key, value)
    local c = ffi.cast("ke_directional_light_component*",
        kernel.ke_ecs_component_get(registry, entity, dir_cid))
    local k = ffi.string(key)
    if k == "direction" and value.type == V_VEC3 then
        c.dir_x, c.dir_y, c.dir_z = value.v3.x, value.v3.y, value.v3.z
    elseif k == "color" and value.type == V_VEC3 then
        c.r, c.g, c.b = value.v3.x, value.v3.y, value.v3.z
    elseif k == "intensity" then
        c.intensity = as_float(value)
    end
    return 0
end)

-- ── Camera ──────────────────────────────────────────────────────────────────
local cam_create = cb("ke_node_create_func", function(_ctx, entity, _name)
    local c = ffi.cast("ke_camera_component*",
        kernel.ke_ecs_component_add(registry, entity, cam_cid))
    c.fov               = math.rad(60)
    c.near_plane        = 0.1
    c.far_plane         = 100.0
    c.orthographic_size = 0
    c.orthographic      = 0
    return 0
end)
local cam_set = cb("ke_node_set_property_func", function(_ctx, entity, key, value)
    local c = ffi.cast("ke_camera_component*",
        kernel.ke_ecs_component_get(registry, entity, cam_cid))
    local k = ffi.string(key)
    if     k == "fov_degrees"       then c.fov               = math.rad(as_float(value))
    elseif k == "near"              then c.near_plane        = as_float(value)
    elseif k == "far"               then c.far_plane         = as_float(value)
    elseif k == "orthographic_size" then c.orthographic_size = as_float(value)
    end
    return 0
end)

-- ── Mesh ────────────────────────────────────────────────────────────────────
-- Caches one mesh handle per primitive name; materials are throwaway per node
-- (we re-create on every `color` property). Good enough for a validation scene.
local PRIM_FROM_NAME = { cube = 2, plane = 1, quad = 0, sphere = 3 }
local mesh_handle_cache = {}
local function get_or_bake(name)
    local cached = mesh_handle_cache[name]
    if cached then return cached end
    local prim = PRIM_FROM_NAME[name]
    if not prim then return nil end
    local shape = ffi.new("ke_mesh_shape_data")
    assert(framework.ke_mesh_shape_bake(alloc, prim, 0, shape) == 0)
    local out = ffi.new("ke_mesh_handle[1]")
    assert(render.create_mesh(render, shape.vertices, shape.vertex_count,
                              shape.indices, shape.index_count, out) == 0)
    framework.ke_mesh_shape_free(alloc, shape)
    mesh_handle_cache[name] = out[0]
    return out[0]
end

local mesh_create = cb("ke_node_create_func", function(_ctx, entity, _name)
    local c = ffi.cast("ke_mesh_component*",
        kernel.ke_ecs_component_add(registry, entity, mesh_cid))
    c.mesh.idx     = 0xFFFFFFFF
    c.material.idx = 0xFFFFFFFF
    return 0
end)
local mesh_set = cb("ke_node_set_property_func", function(_ctx, entity, key, value)
    local c = ffi.cast("ke_mesh_component*",
        kernel.ke_ecs_component_get(registry, entity, mesh_cid))
    local k = ffi.string(key)
    if k == "primitive" and value.type == V_STRING then
        local h = get_or_bake(ffi.string(value.s))
        if h then c.mesh = h end
    elseif k == "color" and (value.type == V_VEC3 or value.type == V_VEC4) then
        local mat = ffi.new("ke_material")
        mat.r, mat.g, mat.b = value.v3.x, value.v3.y, value.v3.z
        mat.a = (value.type == V_VEC4) and value.v4.w or 1.0
        mat.albedo.idx     = 0
        mat.metallic       = 0.0
        mat.roughness      = 0.7
        mat.normal_map.idx = 0xFFFFFFFF
        local mh = ffi.new("ke_material_handle[1]")
        assert(render.create_material(render, mat, mh) == 0)
        c.material = mh[0]
    end
    return 0
end)

local function make_node_type(name, create_fn, set_fn)
    local nt = ffi.new("ke_node_type")
    nt.name         = name
    nt.ctx          = nil
    nt.create       = create_fn
    nt.set_property = set_fn
    return nt
end

local node_registry_out = ffi.new("ke_node_type_registry*[1]")
assert(framework.ke_node_type_registry_create(alloc, node_registry_out) == 0)
local node_registry = node_registry_out[0]
local types_anchor = { -- register_type copies the descriptor; keep originals alive anyway
    make_node_type("DirectionalLight", dir_create,  dir_set),
    make_node_type("Camera",           cam_create,  cam_set),
    make_node_type("Mesh",             mesh_create, mesh_set),
}
for _, nt in ipairs(types_anchor) do
    assert(node_registry.register_type(node_registry, nt) == 0)
end

-- ── Load the scene ──────────────────────────────────────────────────────────
local loader_out = ffi.new("ke_scene_loader*[1]")
-- NULL project_root → nested res:// paths resolve relative to the loading
-- scene's own directory, which is what we want.
assert(framework.ke_scene_loader_create(alloc, world, tree, node_registry,
                                        nil, loader_out) == 0)
local loader = loader_out[0]
assert(loader.load(loader, script_dir .. "scenes/Main.scene") == 0)

-- Static frame state: set once. Re-assigning every frame triggered a LuaJIT
-- trace bug (`'short' cannot be indexed with 'number'` at tick 2).
packet.clear_color[0] = 0.08; packet.clear_color[1] = 0.10
packet.clear_color[2] = 0.15; packet.clear_color[3] = 1.0
packet.ambient_light[0] = 0.15; packet.ambient_light[1] = 0.15; packet.ambient_light[2] = 0.18

-- ── Input actions — Pong bindings registered programmatically ───────────────

local actions_out = ffi.new("ke_input_actions*[1]")
assert(framework.ke_input_actions_create(alloc, actions_out) == 0)
local actions = actions_out[0]

local PADDLE_LEFT  = actions.add_action(actions, "PaddleLeftMove",  ffi.C.KE_ACTION_TYPE_AXIS1D)
local PADDLE_RIGHT = actions.add_action(actions, "PaddleRightMove", ffi.C.KE_ACTION_TYPE_AXIS1D)
local LAUNCH       = actions.add_action(actions, "Launch",          ffi.C.KE_ACTION_TYPE_BUTTON)
local QUIT         = actions.add_action(actions, "Quit",            ffi.C.KE_ACTION_TYPE_BUTTON)
assert(actions.bind_key_pair(actions, PADDLE_LEFT,  ffi.C.KE_KEY_S,    ffi.C.KE_KEY_W)    == 0)
assert(actions.bind_key_pair(actions, PADDLE_RIGHT, ffi.C.KE_KEY_DOWN, ffi.C.KE_KEY_UP)   == 0)
assert(actions.bind_key      (actions, LAUNCH,                          ffi.C.KE_KEY_SPACE)  == 0)
assert(actions.bind_key      (actions, QUIT,                            ffi.C.KE_KEY_ESCAPE) == 0)

-- ── Frame loop ──────────────────────────────────────────────────────────────

local snapshot   = ffi.new("ke_input_snapshot")
local frame_evt  = ffi.new("ke_frame")
local dt         = 1.0 / 60.0
local frames     = 0
local total      = 0.0
-- KE_MAX_FRAMES=N caps the loop for unattended testing; unset = run until close.
local MAX_FRAMES = tonumber(os.getenv("KE_MAX_FRAMES"))

while app.window.should_close(app.window) == 0
      and (not MAX_FRAMES or frames < MAX_FRAMES) do
    app.window.poll_events(app.window)
    app.input.update(app.input)
    app.input.get_snapshot(app.input, snapshot)
    actions.evaluate(actions, snapshot, nil, nil)
    if actions.is_action_down(actions, QUIT) then break end

    frame_evt.frame_index = frames
    frame_evt.delta_time  = dt
    frame_evt.total_time  = total
    frame_evt.input       = snapshot
    world.update(world, frame_evt) -- ScriptSystem + TransformSystem

    -- Drive native render systems manually until world.update threads the
    -- packet through to registered systems (bug #4).
    kernel.ke_frame_packet_reset(packet)
    app.cam_update.update  (app.cam_update.handle,   world, dt, packet)
    app.mesh_update.update (app.mesh_update.handle,  world, dt, packet)
    app.light_update.update(app.light_update.handle, world, dt, packet)
    render.submit_packet(render, packet)
    render.frame(render)

    frames = frames + 1
    total  = total + dt
end

-- ── Shutdown ────────────────────────────────────────────────────────────────

actions.destroy(actions)
loader.destroy(loader)
node_registry.destroy(node_registry)
framework.ke_camera_render_system_destroy(app.cam_sys)
framework.ke_mesh_render_system_destroy(app.mesh_sys)
framework.ke_light_render_system_destroy(app.light_sys)
kernel.ke_frame_packet_destroy(alloc, packet)
for _, h in pairs(mesh_handle_cache) do render.destroy_mesh(render, h) end
tree.destroy(tree)
world.destroy(world)
render.on_shutdown(render)
render.destroy(render)
app.window.on_shutdown(app.window)
app.window.destroy(app.window)
app.input.destroy(app.input)
app.logger.destroy(app.logger)
alloc.destroy(alloc)
