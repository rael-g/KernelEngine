-- Pong in Lua over LuaJIT FFI.
-- This is the canonical "framework migration validator" example: anything the
-- Lua side cannot call directly on the C ABI is a gap to port from the C#
-- Framework into the C/C++ framework plugin. We grow the cdef block + Lua
-- helpers below as gaps close.
--
-- Run from build/native/bin:
--   build/win/vcpkg_installed/x64-windows-static-md/tools/luajit/luajit.exe ../../../examples/lua/pong/main.lua

local ffi = require("ffi")

-- ── Kernel core: allocator + logger + log levels ────────────────────────────

ffi.cdef[[
typedef int ke_result;

typedef struct ke_allocator {
    void *handle;
    void  (*destroy)(struct ke_allocator *self);
    void *(*alloc)  (struct ke_allocator *self, size_t size, size_t alignment);
    void  (*free)   (struct ke_allocator *self, void *ptr);
    void *(*realloc)(struct ke_allocator *self, void *ptr, size_t new_size);
    void  (*reset)  (struct ke_allocator *self);
} ke_allocator;

ke_allocator *ke_allocator_malloc_create(void);

typedef struct ke_log_event {
    int32_t     level;
    const char *tag;
    const char *message;
} ke_log_event;

typedef struct ke_logger_sink {
    void   *handle;
    int32_t min_level;
    void  (*log)    (struct ke_logger_sink *self, const ke_log_event *event);
    void  (*flush)  (struct ke_logger_sink *self);
    void  (*destroy)(struct ke_logger_sink *self);
} ke_logger_sink;

typedef struct ke_logger {
    void          *handle;
    int32_t        runtime_limit;
    ke_allocator  *allocator;
    void      (*destroy)(struct ke_logger *self);
    void      (*log)    (struct ke_logger *self, const ke_log_event *event);
    void      (*flush)  (struct ke_logger *self);
    ke_result (*add_sink)(struct ke_logger *self, ke_logger_sink sink);
} ke_logger;

ke_result ke_logger_create(ke_allocator *allocator, ke_logger **out_logger);

// ── Thread name (kernel TLS) ─────────────────────────────────────────────
void        ke_thread_set_current_name(const char *name);
const char *ke_thread_get_current_name(void);
void        ke_thread_assert_current  (const char *expected_name);

// ── Input ────────────────────────────────────────────────────────────────
typedef uint8_t ke_bool;

typedef struct ke_input_snapshot ke_input_snapshot; // opaque to Lua for now

typedef struct ke_input_event ke_input_event; // opaque

typedef struct ke_input {
    void   *handle;
    struct ke_allocator *allocator;
    struct ke_logger    *logger;
    void   (*destroy)(struct ke_input *self);
    ke_result (*update)(struct ke_input *self);
    ke_bool  (*is_key_pressed) (struct ke_input *self, int32_t key);
    ke_bool  (*is_key_released)(struct ke_input *self, int32_t key);
    ke_bool  (*is_key_down)    (struct ke_input *self, int32_t key);
    void     (*get_snapshot)   (struct ke_input *self, ke_input_snapshot *out_snapshot);
    uint32_t (*drain_events)   (struct ke_input *self, ke_input_event *out_buf, uint32_t capacity);
    // Event sinks (main-thread only) — declared so the vtable offsets match the C header.
    void (*on_key)         (struct ke_input *self, int32_t key, int32_t action);
    void (*on_mouse_move)  (struct ke_input *self, float x, float y);
    void (*on_mouse_button)(struct ke_input *self, int32_t button, int32_t action);
    void (*on_mouse_scroll)(struct ke_input *self, float dx, float dy);
} ke_input;

ke_result ke_input_create(struct ke_allocator *allocator, struct ke_logger *logger, ke_input **out_input);

// ── Window ───────────────────────────────────────────────────────────────
typedef struct ke_window {
    void   *handle;
    void  (*destroy)(struct ke_window *self);
    ke_result (*on_initialize)(struct ke_window *self);
    ke_result (*on_shutdown)  (struct ke_window *self);
    ke_bool   (*should_close) (struct ke_window *self);
    ke_result (*poll_events)  (struct ke_window *self);
    ke_result (*swap_buffers) (struct ke_window *self);
    ke_result (*get_size)     (struct ke_window *self, int32_t *w, int32_t *h);
    void *(*get_native_handle)(struct ke_window *self);
} ke_window;

// GLFW plugin factory
typedef struct ke_window_glfw_params {
    struct ke_allocator *allocator;
    struct ke_logger    *logger;
    struct ke_input     *input;
    const char          *title;
    int32_t              width;
    int32_t              height;
    ke_bool              fullscreen;
} ke_window_glfw_params;

ke_result ke_window_glfw_create(const ke_window_glfw_params *params, ke_window **out_window);

// ── Render ───────────────────────────────────────────────────────────────
// Opaque pointers (Lua doesn't touch the layout for these types, only forwards them).
typedef struct ke_mat4              ke_mat4;
typedef struct ke_vertex            ke_vertex;
typedef struct ke_material          ke_material;
typedef struct ke_directional_light ke_directional_light;
typedef struct ke_point_light       ke_point_light;
typedef struct ke_spot_light        ke_spot_light;
typedef struct ke_cluster_config    ke_cluster_config;
typedef struct ke_frame_packet      ke_frame_packet;
typedef struct ke_render_graph      ke_render_graph;
typedef struct ke_mesh_handle      { uint32_t idx; } ke_mesh_handle;
typedef struct ke_material_handle  { uint32_t idx; } ke_material_handle;
typedef struct ke_texture_handle   { uint32_t idx; } ke_texture_handle;
typedef struct ke_shadow_map_handle{ uint32_t idx; } ke_shadow_map_handle;

typedef struct ke_ndc_convention { ke_bool y_flip; ke_bool zero_to_one_depth; } ke_ndc_convention;

typedef struct ke_render {
    void *handle;
    void  (*destroy)(struct ke_render *self);

    ke_result (*on_initialize)(struct ke_render *self);
    ke_result (*on_shutdown)  (struct ke_render *self);

    ke_result (*set_orthographic)(struct ke_render *self, ke_bool enabled);
    ke_result (*clear_color)     (struct ke_render *self, float r, float g, float b, float a);

    ke_result (*frame)(struct ke_render *self);
    ke_result (*set_view_transform)(struct ke_render *self, const ke_mat4 *view, const ke_mat4 *proj);

    ke_ndc_convention (*get_ndc_convention)(struct ke_render *self);

    ke_result (*create_mesh)   (struct ke_render *self, const ke_vertex *vertices, uint32_t vc,
                                const uint16_t *indices, uint32_t ic, ke_mesh_handle *out);
    ke_result (*destroy_mesh)  (struct ke_render *self, ke_mesh_handle handle);
    ke_result (*create_material)(struct ke_render *self, const ke_material *mat, ke_material_handle *out);
    ke_result (*destroy_material)(struct ke_render *self, ke_material_handle handle);
    ke_result (*submit_mesh)   (struct ke_render *self, ke_mesh_handle mesh, ke_material_handle mat,
                                const ke_mat4 *transform);

    ke_result (*create_texture_rgba)(struct ke_render *self, uint32_t w, uint32_t h,
                                     const uint8_t *pixels, ke_texture_handle *out);
    ke_result (*destroy_texture)(struct ke_render *self, ke_texture_handle handle);

    ke_result (*set_directional_light)(struct ke_render *self, const ke_directional_light *light);
    ke_result (*set_ambient_light)(struct ke_render *self, float r, float g, float b);
    ke_result (*set_camera_pos)   (struct ke_render *self, float x, float y, float z);

    ke_result (*create_cubemap_rgba)(struct ke_render *self, uint32_t size, const uint8_t *data,
                                     ke_texture_handle *out);
    ke_result (*submit_skybox)      (struct ke_render *self, ke_texture_handle cubemap);

    ke_result (*create_shadow_map) (struct ke_render *self, uint32_t w, uint32_t h, ke_shadow_map_handle *out);
    ke_result (*destroy_shadow_map)(struct ke_render *self, ke_shadow_map_handle handle);
    ke_result (*begin_shadow_pass) (struct ke_render *self, ke_shadow_map_handle handle,
                                    const ke_mat4 *light_view, const ke_mat4 *light_proj);
    ke_result (*submit_mesh_shadow)(struct ke_render *self, ke_mesh_handle mesh, const ke_mat4 *transform);
    ke_result (*end_shadow_pass)   (struct ke_render *self);
    ke_result (*set_shadow_map)    (struct ke_render *self, ke_shadow_map_handle handle);

    ke_result (*set_tonemapping)(struct ke_render *self, ke_bool enabled, float exposure, float gamma);
    ke_result (*set_bloom)      (struct ke_render *self, ke_bool enabled, float threshold, float intensity);

    ke_result (*set_point_lights)(struct ke_render *self, const ke_point_light *lights, uint32_t count);
    ke_result (*set_spot_lights) (struct ke_render *self, const ke_spot_light *lights, uint32_t count);
    ke_result (*set_ssao)        (struct ke_render *self, ke_bool enabled, float radius, float bias, float strength);
    ke_result (*set_cluster_config)(struct ke_render *self, const ke_cluster_config *config);

    ke_result (*submit_ui_quad)(struct ke_render *self, ke_texture_handle texture,
                                float dx, float dy, float dw, float dh,
                                float u0, float v0, float u1, float v1,
                                float r, float g, float b, float a);

    ke_result (*submit_packet)(struct ke_render *self, const struct ke_frame_packet *packet);
    const char *(*get_last_fatal_error)(struct ke_render *self);

    struct ke_render_graph *(*create_render_graph)(struct ke_render *self, struct ke_allocator *allocator);
    struct ke_render_graph *(*get_render_graph)   (struct ke_render *self);
} ke_render;

typedef struct ke_render_bgfx_params {
    struct ke_allocator *allocator;
    struct ke_logger    *logger;
    struct ke_window    *window;
    const char          *shader_path;
    uint32_t             renderer_type; // 0 = Vulkan default
    ke_bool              vsync;
} ke_render_bgfx_params;

ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render);

// ── World + ECS ─────────────────────────────────────────────────────────
typedef uint64_t ke_entity;
typedef uint32_t ke_component_id;
typedef struct ke_frame ke_frame; // opaque
typedef struct ke_system_params ke_system_params; // opaque
typedef struct ke_task_scheduler ke_task_scheduler; // opaque
typedef struct ke_ecs_registry {
    struct ke_allocator *allocator;
    ke_entity            next_entity;
    void                *internal_data;
} ke_ecs_registry;

typedef struct ke_world_params {
    struct ke_allocator *allocator;
} ke_world_params;

typedef struct ke_world {
    void                *handle;
    struct ke_allocator *allocator;
    struct ke_ecs_registry *registry;
    void                *internal_data;
    void  (*destroy)(struct ke_world *self);
    ke_result (*update)(struct ke_world *self, const struct ke_frame *frame);
    struct ke_ecs_registry *(*get_registry)(struct ke_world *self);
    ke_result (*add_system)(struct ke_world *self, const ke_system_params *params);
    uint32_t (*transform_id)(struct ke_world *self);
    uint32_t (*hierarchy_id)(struct ke_world *self);
    uint32_t (*name_id)     (struct ke_world *self);
    uint32_t (*script_id)   (struct ke_world *self);
    struct ke_task_scheduler *(*get_task_scheduler)(struct ke_world *self);
} ke_world;

ke_result ke_world_create(const ke_world_params *params, ke_world **out_world);

// ── Scene tree (framework plugin) ───────────────────────────────────────
typedef struct ke_scene_tree {
    void     *handle;
    ke_entity (*root)        (struct ke_scene_tree *self);
    ke_entity (*create_node) (struct ke_scene_tree *self, const char *name, ke_entity parent);
    ke_result (*destroy_node)(struct ke_scene_tree *self, ke_entity entity);
    void      (*destroy_all) (struct ke_scene_tree *self);
    ke_entity (*find_node)   (struct ke_scene_tree *self, const char *name_or_path);
    void      (*destroy)     (struct ke_scene_tree *self);
} ke_scene_tree;

ke_result ke_scene_tree_create(struct ke_world *world, struct ke_allocator *alloc, ke_scene_tree **out_tree);

// ── Frame + scripting (per-entity lifecycle callbacks dispatched by the native ScriptSystem)
typedef struct ke_input_snapshot ke_input_snapshot; // already opaque elsewhere

typedef struct ke_frame {
    uint64_t                 frame_index;
    double                   delta_time;
    double                   total_time;
    const ke_input_snapshot *input;
} ke_frame;

typedef ke_result (*ke_script_func)        (ke_entity entity);
typedef ke_result (*ke_script_update_func) (ke_entity entity, float dt);
typedef ke_result (*ke_script_input_func)  (ke_entity entity, const ke_input_snapshot *input);

typedef struct ke_script_component {
    uint8_t                state; // KE_SCRIPT_STATE_FRESH=0 / AWOKE=1 / STARTED=2
    ke_script_func         on_awake;
    ke_script_func         on_start;
    ke_script_update_func  on_update;
    ke_script_update_func  on_late_update;
    ke_script_func         on_destroy;
    ke_script_input_func   on_input;
} ke_script_component;

// ECS slots we need to attach + look up the script component on entities.
void  *ke_ecs_component_add(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);
void  *ke_ecs_component_get(ke_ecs_registry *registry, ke_entity entity, ke_component_id component);

// ── Input snapshot (layout matches src/c/kernel/include/kernel_engine/kernel/input/snapshot.h)
typedef struct ke_input_snapshot {
    uint64_t keys_down[8];
    uint64_t keys_pressed[8];
    uint64_t keys_released[8];
    float    mouse_x, mouse_y;
    float    mouse_dx, mouse_dy;
    float    scroll_dx, scroll_dy;
    uint32_t mouse_buttons_down;
    uint32_t mouse_buttons_pressed;
    uint32_t mouse_buttons_released;
} ke_input_snapshot;

// ── Input actions (framework plugin) ────────────────────────────────────────
typedef int  ke_action_type;
typedef int  ke_action_phase;
typedef int  ke_key;
typedef int  ke_mouse_button;

typedef struct ke_input_action_event {
    int32_t          action_id;
    ke_action_type   type;
    ke_action_phase  phase;
    float            x, y, z;
} ke_input_action_event;

typedef void (*ke_input_action_event_func)(void *ctx, ke_input_action_event event);

typedef struct ke_input_actions {
    void *handle;
    ke_result (*load)(struct ke_input_actions *self, const char *path);
    int32_t   (*get_action_id)(struct ke_input_actions *self, const char *name);
    int32_t   (*add_action)(struct ke_input_actions *self, const char *name, ke_action_type type);
    ke_result (*bind_key)(struct ke_input_actions *self, int32_t action_id, ke_key key);
    ke_result (*bind_mouse_button)(struct ke_input_actions *self, int32_t action_id, ke_mouse_button button);
    ke_result (*bind_key_pair)(struct ke_input_actions *self, int32_t action_id, ke_key neg, ke_key pos);
    ke_result (*bind_key_quad)(struct ke_input_actions *self, int32_t action_id,
                               ke_key up, ke_key down, ke_key left, ke_key right);
    ke_result (*evaluate)(struct ke_input_actions *self, const ke_input_snapshot *snap,
                          ke_input_action_event_func on_event, void *ctx);
    bool      (*is_action_down)     (struct ke_input_actions *self, int32_t action_id);
    bool      (*was_action_pressed) (struct ke_input_actions *self, int32_t action_id);
    bool      (*was_action_released)(struct ke_input_actions *self, int32_t action_id);
    float     (*get_axis1d)(struct ke_input_actions *self, int32_t action_id);
    void      (*get_axis2d)(struct ke_input_actions *self, int32_t action_id, float *x, float *y);
    void      (*get_axis3d)(struct ke_input_actions *self, int32_t action_id, float *x, float *y, float *z);
    void      (*destroy)   (struct ke_input_actions *self);
} ke_input_actions;

ke_result ke_input_actions_create(ke_allocator *alloc, ke_input_actions **out_actions);

// Action type / phase / key enum values used below (mirrors the C headers).
enum {
    KE_ACTION_TYPE_BUTTON = 0,
    KE_ACTION_TYPE_AXIS1D = 1,
    KE_KEY_SPACE  = 32,
    KE_KEY_S      = 83,
    KE_KEY_W      = 87,
    KE_KEY_UP     = 265,
    KE_KEY_DOWN   = 264,
    KE_KEY_ESCAPE = 256,
};
]]

-- Resolve dll directory from the script's own path so this runs from any CWD.
-- examples/lua/pong/main.lua → ../../../build/native/bin/. We register the dir
-- with the Windows loader (SetDllDirectoryA) so transitive deps like ke_threading
-- resolve from the same folder without requiring CWD or PATH tweaks.
local script_path = arg[0] or "examples/lua/pong/main.lua"
local script_dir  = script_path:gsub("[^/\\]+$", "")
local bin_dir     = script_dir .. "../../../build/native/bin/"
ffi.cdef[[ int SetDllDirectoryA(const char *path); ]]
ffi.C.SetDllDirectoryA((bin_dir:gsub("/", "\\")))

local kernel       = ffi.load("ke_kernel")
local window_glfw  = ffi.load("ke_window_glfw")
local render_bgfx  = ffi.load("ke_render_bgfx")
local framework    = ffi.load("ke_framework")

local LOG_TRACE, LOG_DEBUG, LOG_INFO, LOG_WARN, LOG_ERROR, LOG_FATAL = 0, 1, 2, 3, 4, 5
local LEVEL_NAMES = { [0]="TRACE", [1]="DEBUG", [2]="INFO", [3]="WARN", [4]="ERROR", [5]="FATAL" }

-- ── Lua-side console sink (gap: no native console sink yet) ─────────────────
-- The C# Framework ships ConsoleSink/Serilog. Here we wire a Lua function as a
-- ke_logger_sink callback. ffi.cast keeps the cdata alive for the lifetime of
-- the cast; storing it in a Lua-side table prevents premature GC.
local sink_cbs = {}
sink_cbs.log = ffi.cast("void (*)(ke_logger_sink*, const ke_log_event*)", function(_self, event)
    local lvl = LEVEL_NAMES[event.level] or "?"
    local tag = event.tag ~= nil and ffi.string(event.tag) or ""
    local msg = event.message ~= nil and ffi.string(event.message) or ""
    io.write(string.format("[%-5s] %s: %s\n", lvl, tag, msg))
end)
sink_cbs.flush   = ffi.cast("void (*)(ke_logger_sink*)", function() io.flush() end)
sink_cbs.destroy = ffi.cast("void (*)(ke_logger_sink*)", function() end)

-- ── Bootstrap: allocator → logger → sink → log a message ────────────────────

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
sink.min_level = LOG_TRACE
sink.log       = sink_cbs.log
sink.flush     = sink_cbs.flush
sink.destroy   = sink_cbs.destroy
assert(logger.add_sink(logger, sink) == 0)

-- First successful Lua → kernel → Lua roundtrip
local event = ffi.new("ke_log_event")
event.level   = LOG_INFO
event.tag     = "lua_pong"
event.message = "hello from pong.lua"
logger.log(logger, event)

-- ── Input + Window ──────────────────────────────────────────────────────────

local input_out = ffi.new("ke_input*[1]")
assert(kernel.ke_input_create(alloc, logger, input_out) == 0)
local input = input_out[0]

local win_params = ffi.new("ke_window_glfw_params")
win_params.allocator  = alloc
win_params.logger     = logger
win_params.input      = input
win_params.title      = "Pong (Lua over LuaJIT FFI)"
win_params.width      = 960
win_params.height     = 540
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
local shader_path_str   = bin_dir .. "shaders"
rb_params.shader_path   = shader_path_str
rb_params.renderer_type = 0
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

local root = tree.root(tree)
io.write(string.format("[scene] root entity = %d\n", tonumber(root)))
local sun       = tree.create_node(tree, "Sun",       root)
local floor_ent = tree.create_node(tree, "Floor",     root)
local cube_ent  = tree.create_node(tree, "Caster",    root)
io.write(string.format("[scene] created nodes: Sun=%d Floor=%d Caster=%d\n",
    tonumber(sun), tonumber(floor_ent), tonumber(cube_ent)))

local found = tree.find_node(tree, "Floor")
io.write(string.format("[scene] find_node('Floor') = %d (expected %d)\n",
    tonumber(found), tonumber(floor_ent)))
assert(found == floor_ent, "find_node round-trip mismatch")

-- ── Script hook on Sun — proof the native ScriptSystem dispatches into Lua ──

local script_cid = world.script_id(world)
local registry   = world.get_registry(world)

local script_callbacks = {} -- anchor callbacks so they outlive GC
local update_count = 0
script_callbacks.on_start = ffi.cast("ke_script_func", function(entity)
    io.write(string.format("[script] on_start  entity=%d\n", tonumber(entity)))
    io.flush()
    return 0
end)
script_callbacks.on_update = ffi.cast("ke_script_update_func", function(entity, dt)
    update_count = update_count + 1
    if update_count <= 3 or update_count % 60 == 0 then
        io.write(string.format("[script] on_update entity=%d dt=%.4f (tick %d)\n",
            tonumber(entity), dt, update_count))
        io.flush()
    end
    return 0
end)

local sc = ffi.cast("ke_script_component*",
    kernel.ke_ecs_component_add(registry, sun, script_cid))
sc.state          = 0 -- KE_SCRIPT_STATE_FRESH
sc.on_awake       = nil
sc.on_start       = script_callbacks.on_start
sc.on_update      = script_callbacks.on_update
sc.on_late_update = nil
sc.on_destroy     = nil
sc.on_input       = nil

io.write("[script] component attached on Sun; entering world.update loop\n")

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
io.write(string.format("[actions] ids = PaddleLeft=%d PaddleRight=%d Launch=%d Quit=%d\n",
    PADDLE_LEFT, PADDLE_RIGHT, LAUNCH, QUIT))

local snapshot = ffi.new("ke_input_snapshot")
local prev_left, prev_right, prev_launch = 0.0, 0.0, false

-- ── Frame loop ──────────────────────────────────────────────────────────────
-- Cycles the clear color so we get visual confirmation the renderer is alive
-- (no scene yet — that requires ke_world + scene tree + render systems, next gaps).

local frames    = 0
local total     = 0.0
local frame_evt = ffi.new("ke_frame")
local dt        = 1.0 / 60.0 -- fixed step until we wire a real clock
while win.should_close(win) == 0 do
    win.poll_events(win)
    input.update(input)

    input.get_snapshot(input, snapshot)
    actions.evaluate(actions, snapshot, nil, nil)

    if actions.is_action_down(actions, QUIT) then break end
    local left  = actions.get_axis1d(actions, PADDLE_LEFT)
    local right = actions.get_axis1d(actions, PADDLE_RIGHT)
    local launch = actions.was_action_pressed(actions, LAUNCH)
    if left ~= prev_left or right ~= prev_right or launch ~= prev_launch then
        io.write(string.format("[actions] left=%.1f right=%.1f launch=%s\n",
            left, right, tostring(launch)))
        io.flush()
        prev_left, prev_right, prev_launch = left, right, launch
    end

    frame_evt.frame_index = frames
    frame_evt.delta_time  = dt
    frame_evt.total_time  = total
    frame_evt.input       = snapshot
    world.update(world, frame_evt)

    local t = total
    render.clear_color(render, 0.5 + 0.5 * math.sin(t),
                                0.5 + 0.5 * math.sin(t * 1.3),
                                0.5 + 0.5 * math.sin(t * 1.7),
                                1.0)
    render.frame(render)
    frames = frames + 1
    total  = total + dt
end

io.write(string.format("[loop] exited after %d frames\n", frames))

-- ── Shutdown ────────────────────────────────────────────────────────────────

actions.destroy(actions)
tree.destroy(tree)
world.destroy(world)
render.on_shutdown(render)
render.destroy(render)
win.on_shutdown(win)
win.destroy(win)
input.destroy(input)
logger.destroy(logger)
alloc.destroy(alloc)

print("[bootstrap] kernel + glfw + bgfx round-trip OK")
