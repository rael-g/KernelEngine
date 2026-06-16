-- Pong in Lua over LuaJIT FFI — ECS-pure-nodes branch.
--
-- All scene content lives in scenes/Main.scene as `[[entity]] [components.X]`.
-- The SceneLoader writes into ECS components by name + offset (zero binding
-- code per type). The MeshAssetSystem turns the `primitive` + `color` fields
-- on each ke_mesh_component into actual handles the first frame it sees them.

local ffi = require("ffi")

local script_dir = (arg[0] or ""):gsub("[^/\\]+$", "")
if script_dir == "" then script_dir = "." end
local app = dofile(script_dir .. "bootstrap.lua")

local alloc, framework, kernel, render = app.alloc, app.framework, app.kernel, app.render
local world, tree, packet              = app.world, app.tree, app.packet

-- ── Asset system + scene loader ─────────────────────────────────────────────
-- Phase 3 of ECS-pure nodes: a native asset system bakes primitives and
-- creates materials from the fields the loader wrote into each mesh entity.

local asset_sys_params = ffi.new("ke_mesh_asset_system_params")
asset_sys_params.world       = world
asset_sys_params.allocator   = alloc
asset_sys_params.render      = render
asset_sys_params.mesh_system = app.mesh_sys
local asset_sys_out = ffi.new("ke_mesh_asset_system*[1]")
assert(framework.ke_mesh_asset_system_create(asset_sys_params, asset_sys_out) == 0)
local asset_sys = asset_sys_out[0]
local asset_sys_params_v = ffi.new("ke_system_params")
framework.ke_mesh_asset_system_get_system_params(asset_sys, asset_sys_params_v)

local loader_out = ffi.new("ke_scene_loader*[1]")
assert(framework.ke_scene_loader_create(world, nil, loader_out) == 0)
local loader = loader_out[0]
assert(loader.load(loader, script_dir .. "scenes/Main.scene") == 0)

-- Static frame state: set once. Re-assigning every frame triggered a LuaJIT
-- trace bug (`'short' cannot be indexed with 'number'` at tick 2).
packet.clear_color[0] = 0.08; packet.clear_color[1] = 0.10
packet.clear_color[2] = 0.15; packet.clear_color[3] = 1.0
packet.ambient_light[0] = 0.15; packet.ambient_light[1] = 0.15; packet.ambient_light[2] = 0.18

-- ── Input actions — Pong bindings registered programmatically ───────────────

local actions_out = ffi.new("ke_input_actions*[1]")
assert(framework.ke_input_actions_create(actions_out) == 0)
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
    -- packet through to registered systems (bug #4). Asset system runs first
    -- so the scene-loaded primitive→mesh / color→material handles are ready
    -- by the time the mesh render system queries the component.
    kernel.ke_frame_packet_reset(packet)
    asset_sys_params_v.update(asset_sys_params_v.handle, world, dt, packet)
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
framework.ke_mesh_asset_system_destroy(asset_sys) -- frees cached mesh handles
framework.ke_camera_render_system_destroy(app.cam_sys)
framework.ke_mesh_render_system_destroy(app.mesh_sys)
framework.ke_light_render_system_destroy(app.light_sys)
kernel.ke_frame_packet_destroy(alloc, packet)
tree.destroy(tree)
world.destroy(world)
render.on_shutdown(render)
render.destroy(render)
app.window.on_shutdown(app.window)
app.window.destroy(app.window)
app.input.destroy(app.input)
app.logger.destroy(app.logger)
alloc.destroy(alloc)
