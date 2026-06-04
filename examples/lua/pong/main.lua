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
]]

local kernel = ffi.load("ke_kernel")
local window_glfw = ffi.load("ke_window_glfw")

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

-- ── Frame loop (single-threaded for now — threading + renderer come next) ───

local frames = 0
while win.should_close(win) == 0 do
    win.poll_events(win)
    input.update(input)
    frames = frames + 1
end

io.write(string.format("[loop] exited after %d frames\n", frames))

-- ── Shutdown ────────────────────────────────────────────────────────────────

win.on_shutdown(win)
win.destroy(win)
input.destroy(input)
logger.destroy(logger)
alloc.destroy(alloc)

print("[bootstrap] kernel + glfw window round-trip OK")
