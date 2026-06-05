-- Engine bootstrap — equivalent to a C# Program.cs (ServiceCollection wiring +
-- new Application()). Loads the kernel + plugin DLLs, opens a window, brings
-- up a logger, creates the world + scene tree + render systems, and allocates
-- a single-buffer frame packet. Returns one table with every handle the host
-- script needs to drive the loop, register node types, and shut down cleanly.
--
-- This file holds zero scene/game logic. Add per-program needs (custom sinks,
-- alternative window sizes, additional systems) in the caller, not here.

local ffi = require("ffi")

-- Resolve dll directory from THIS file's path so the script runs from any CWD.
-- (`debug.getinfo` is the only way to learn the currently-loading file's
-- location; `arg[0]` would refer to the entry point, not the require'd file.)
local this_file = debug.getinfo(1, "S").source:gsub("^@", "")
local script_dir = this_file:gsub("[^/\\]+$", "")
if script_dir == "" then script_dir = "." end

dofile(script_dir .. "ke_ffi.lua")

-- We canonicalise via GetFullPathNameA so the result has no leftover `..\..\`
-- segments — bgfx's shader loader (and the Windows loader itself) misbehaves
-- when the path mixes separators or has too many `..` indirections.
ffi.cdef[[
    int SetDllDirectoryA(const char *path);
    uint32_t GetFullPathNameA(const char *file, uint32_t buf_len,
                              char *buf, char **file_part);
]]
local function abs_path(p)
    local buf = ffi.new("char[1024]")
    local n = ffi.C.GetFullPathNameA(p, 1024, buf, nil)
    if n == 0 or n > 1024 then return p end
    return ffi.string(buf, n)
end

local bin_dir = abs_path(script_dir .. "../../../build/native/bin")
if not bin_dir:match("[/\\]$") then bin_dir = bin_dir .. "\\" end
ffi.C.SetDllDirectoryA(bin_dir)

local kernel       = ffi.load("ke_kernel")
local window_glfw  = ffi.load("ke_window_glfw")
local render_bgfx  = ffi.load("ke_render_bgfx")
local framework    = ffi.load("ke_framework")

-- ── Console sink ────────────────────────────────────────────────────────────
-- No-op for now: doing io.write inside an ffi callback risks a LuaJIT GC panic
-- (the logger flushes from a thread mid-bytecode). A real native console sink
-- in C/C++ is the proper fix — until then we accept silent logging.
local sink_cbs = {
    log     = ffi.cast("void (*)(ke_logger_sink*, const ke_log_event*)", function() end),
    flush   = ffi.cast("void (*)(ke_logger_sink*)", function() end),
    destroy = ffi.cast("void (*)(ke_logger_sink*)", function() end),
}

-- ── Kernel core: allocator → logger (with sink) ─────────────────────────────

-- Single-threaded bring-up: bgfx + window both run on this Lua thread, which
-- the renderer asserts must be tagged "ke.render". Once we split the 3-thread
-- orchestration (ke.main / ke.sim / ke.render), each will tag its own slot.
kernel.ke_thread_set_current_name("ke.render")

local alloc = kernel.ke_allocator_malloc_create()
assert(alloc ~= nil)

local logger_out = ffi.new("ke_logger*[1]")
assert(kernel.ke_logger_create(alloc, logger_out) == 0)
local logger = logger_out[0]

local sink = ffi.new("ke_logger_sink")
sink.handle    = nil
sink.min_level = 0 -- LOG_TRACE
sink.log       = sink_cbs.log
sink.flush     = sink_cbs.flush
sink.destroy   = sink_cbs.destroy
assert(logger.add_sink(logger, sink) == 0)

-- ── Input + Window ──────────────────────────────────────────────────────────

local input_out = ffi.new("ke_input*[1]")
assert(kernel.ke_input_create(alloc, logger, input_out) == 0)
local input = input_out[0]

local WIN_W, WIN_H = 960, 540
local win_params = ffi.new("ke_window_glfw_params")
win_params.allocator  = alloc
win_params.logger     = logger
win_params.input      = input
win_params.title      = "Pong (Lua over LuaJIT FFI)"
win_params.width      = WIN_W
win_params.height     = WIN_H
win_params.fullscreen = 0

local win_out = ffi.new("ke_window*[1]")
assert(window_glfw.ke_window_glfw_create(win_params, win_out) == 0)
local win = win_out[0]
assert(win.on_initialize(win) == 0)

-- ── Renderer ────────────────────────────────────────────────────────────────

local rb_params = ffi.new("ke_render_bgfx_params")
rb_params.allocator     = alloc
rb_params.logger        = logger
rb_params.window        = win
-- shader_path must outlive create + the renderer (bgfx may stash the pointer).
-- Pin it as a local; `params.shader_path` is just a view into the string bytes.
local shader_path_str   = bin_dir .. "shaders"
rb_params.shader_path   = shader_path_str
-- bgfx::RendererType::Direct3D11 = 2. UINT32_MAX = auto-pick (Vulkan today,
-- which has flaky swapchain semaphores → ~1/3 segfaults at frame 1).
rb_params.renderer_type = 2
rb_params.vsync         = 1

local render_out = ffi.new("ke_render*[1]")
assert(render_bgfx.ke_render_bgfx_create(rb_params, render_out) == 0)
local render = render_out[0]
assert(render.on_initialize(render) == 0)

-- ── World + Scene tree ──────────────────────────────────────────────────────

local world_params = ffi.new("ke_world_params")
world_params.allocator = alloc
local world_out = ffi.new("ke_world*[1]")
assert(kernel.ke_world_create(world_params, world_out) == 0)
local world = world_out[0]

local tree_out = ffi.new("ke_scene_tree*[1]")
assert(framework.ke_scene_tree_create(world, alloc, tree_out) == 0)
local tree = tree_out[0]

-- ── Render systems (Camera + Mesh + Light) ──────────────────────────────────

local ndc = render.get_ndc_convention(render)

local cam_sys_params = ffi.new("ke_camera_render_system_params")
cam_sys_params.world                 = world
cam_sys_params.allocator             = alloc
cam_sys_params.ndc_y_flip            = ndc.y_flip
cam_sys_params.ndc_zero_to_one_depth = ndc.z_zero_to_one
cam_sys_params.aspect                = WIN_W / WIN_H
local cam_sys_out = ffi.new("ke_camera_render_system*[1]")
assert(framework.ke_camera_render_system_create(cam_sys_params, cam_sys_out) == 0)
local cam_sys = cam_sys_out[0]

local mesh_sys_params = ffi.new("ke_mesh_render_system_params")
mesh_sys_params.world = world; mesh_sys_params.allocator = alloc
local mesh_sys_out = ffi.new("ke_mesh_render_system*[1]")
assert(framework.ke_mesh_render_system_create(mesh_sys_params, mesh_sys_out) == 0)
local mesh_sys = mesh_sys_out[0]

local light_sys_params = ffi.new("ke_light_render_system_params")
light_sys_params.world = world; light_sys_params.allocator = alloc
local light_sys_out = ffi.new("ke_light_render_system*[1]")
assert(framework.ke_light_render_system_create(light_sys_params, light_sys_out) == 0)
local light_sys = light_sys_out[0]

-- system_params output is via pointer (LuaJIT FFI mishandles struct-by-value
-- return >16 bytes on the MSVC x64 ABI, leaving callback fields nil).
local cam_sys_params_v   = ffi.new("ke_system_params")
local mesh_sys_params_v  = ffi.new("ke_system_params")
local light_sys_params_v = ffi.new("ke_system_params")
framework.ke_camera_render_system_get_system_params(cam_sys,   cam_sys_params_v)
framework.ke_mesh_render_system_get_system_params  (mesh_sys,  mesh_sys_params_v)
framework.ke_light_render_system_get_system_params (light_sys, light_sys_params_v)

-- ── Frame packet (single-buffered — Lua is single-threaded for now) ─────────

local fp_params = ffi.new("ke_frame_packet_params")
fp_params.allocator            = alloc
fp_params.draw_capacity        = 64
fp_params.shadow_draw_capacity = 64
fp_params.point_light_capacity = 32
fp_params.spot_light_capacity  = 32
fp_params.ui_draw_capacity     = 256
local packet_out = ffi.new("ke_frame_packet*[1]")
assert(kernel.ke_frame_packet_create(fp_params, packet_out) == 0)
local packet = packet_out[0]

return {
    -- DLL handles
    kernel       = kernel,
    framework    = framework,
    render_bgfx  = render_bgfx,
    window_glfw  = window_glfw,

    -- Engine handles
    alloc        = alloc,
    logger       = logger,
    input        = input,
    window       = win,
    render       = render,
    world        = world,
    tree         = tree,
    registry     = world.get_registry(world),
    packet       = packet,
    sink_cbs     = sink_cbs, -- anchor: keep alive across program lifetime

    -- Render systems (handle + cid + system_params view for the main loop)
    cam_sys      = cam_sys,
    mesh_sys     = mesh_sys,
    light_sys    = light_sys,
    cam_cid      = framework.ke_camera_render_system_component_id(cam_sys),
    mesh_cid     = framework.ke_mesh_render_system_component_id(mesh_sys),
    dir_cid      = framework.ke_light_render_system_directional_id(light_sys),
    cam_update   = cam_sys_params_v,
    mesh_update  = mesh_sys_params_v,
    light_update = light_sys_params_v,

    -- Filesystem helpers
    script_dir   = nil, -- caller fills with its own location (this file lives elsewhere)
    bin_dir      = bin_dir,
}
