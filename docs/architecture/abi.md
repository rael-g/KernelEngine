# How does a call cross the C ABI, and how does a failure come back?

Layers and file placement are in [layers.md](layers.md). This document is what happens at the
boundary itself.

## What a call looks like

A caller holds a pointer to a contract struct and calls through one of its function-pointer members,
passing the struct back as the first argument: `window->poll_events(window, &error)`
(`src/c/window/kernel_engine/window/window.h`, members from line 22). Nothing is resolved by name at
the call. The only name-resolved symbol is the factory that produced the struct
([layers.md](layers.md#layer-2--a-plugin-exports-one-factory-and-nothing-else)).

A factory takes a `_params` struct and a trailing `ke_error **out_error`
(`src/zig/window/glfw/include/kernel_engine/window/glfw/glfw_window.h:34`).

### What every vtable has in common

A sweep of every header under `src/c/` and every plugin `include/` finds 31 structs that are vtables
(an opaque `void *handle` followed by function-pointer slots), and in all 31:

- `handle` is the **first member** — the one exception to the shape is `ke_gpu_surface_ext`, an
  extension table with three slots and no `handle`
  (`src/c/render/kernel_engine/render/gpu/gpu_surface_ext.h:16-30`);
- every function-pointer member takes the struct itself as its **first parameter**, named `self` —
  271 of them, no exception, though `ke_gpu_surface_ext`'s take it `const`. A slot that is a bare callback type
  (`ke_system_execute_fn`) is not a slot and takes its context instead
  (`src/c/runtime/kernel_engine/runtime/runtime.h:99`).

### Who owns the object behind a vtable

A factory returns an **owner**, a two-member struct `{ ref, destroy }`
(`ke_window_handle`, `window.h:43-47`; 34 of them, none with another member), by value. `ref` is the
vtable pointer and `destroy` takes that same pointer. The factory headers that say what failure looks
like — eleven of them, among them `script_host_create.h:38`,
`src/zig/window/glfw/include/kernel_engine/window/glfw/glfw_window.h:33` and
`src/zig/scheduler/enki/include/kernel_engine/scheduler/enki/enki_scheduler.h:24` — say it is an owner
whose `ref` is `NULL`; the others are silent. Every function declared in those headers that returns a
`ke_*_handle` takes `ke_error **out_error` as its last parameter.

The vtable carries no `destroy` of its own, so whoever receives only the bare `ke_X *` cannot destroy
it: owning is a property of holding the `{ ref, destroy }`. Three vtables carry a `destroy` slot
regardless: `ke_logger_sink` (owned by the logger it is handed to, `logger.h:24`, `:42`),
`ke_gpu_command_encoder` and `ke_gpu_command_buffer`
(`src/c/render/kernel_engine/render/gpu/gpu_commands.h:75`, `:83`).

## How a failure comes back

A call that can fail takes `ke_error **out_error` as its last parameter. On failure the callee
records the error and returns its sentinel — `false`, a null handle, an invalid id. The caller
checks the return; `*out_error` is meaningful only after a failure.

There is no result-code type. `grep -rn ke_result src` finds nothing.

### What the error record holds

`ke_error` has `type`, `message`, `file`, `line` and `cause`
(`src/zig/common/include/kernel_engine/common/error.h:41`). It lives in per-thread storage:

- two slots per thread, so wrapping an error with `KE_ERROR_WRAP` keeps the inner one valid while
  the outer is built (`src/zig/common/src/error.zig:20`);
- the message is copied into the slot and truncated at 512 bytes, never allocated, so a failing path
  does not depend on the allocator (`error.zig:21`, `error.zig:58`).

A pointer to a `ke_error` is therefore valid until the next two failures **on the same thread**
(`error.h:38-40`). Copy what must outlive that.

### What an error's type is

`ke_error_type` is a node with a `name` and a `parent` (`error.h:30-33`). Types form a tree; a domain
declares its own beside its own API and points `parent` at a generic root
(`error.h:12-32`). `ke_error_is` walks from the error's type up through `parent`, comparing node
addresses (`error.zig:32-40`).

The eight generic roots are exported by `ke_common` (`error.zig:23-30`). A Zig plugin that cannot
link `ke_common` fills the error through `Errors(c).fail` in `src/zig/common/kerror.zig:62`, which
uses a set of type nodes of its own (`kerror.zig:46-49`).

The managed side matches by name, walking `Parent`
(`src/csharp/common/KernelEngine.Common/KernelErrorType.cs:26-32`).

### The one sanctioned way to end the process

`ke_error_fatal` prints the chain and terminates (`error.h:83-94`); the header reserves it for a
caller that has an error and nowhere left to send it. The one engine call site is the flecs abort
hook (`src/zig/ecs/flecs/src/ecs_flecs.zig:38`, [ecs.md](ecs.md#what-a-flecs-internal-failure-does)).

## Booleans

`ke_bool` is a `uint8_t` (`src/zig/common/include/kernel_engine/common/types.h:13`), which
exists because C `bool` is not blittable through P/Invoke (`types.h:11-12`).

## Doc tags

A `///` or `/** */` comment on a contract member may open with bracketed tags that state what the
signature cannot: `[out]` on a parameter the callee writes (`window.h:34`), `[borrowed,nullable]` on
a pointer the callee does not own and may receive as null (`glfw_window.h:25`). kabic reads them
(`src/csharp/kabic/Kabic.Frontend/DocParser.cs:9`) and projects them into each target language; a
tag that is not there is a fact no projection can recover.

## How a resource is named

The ABI names a resource by a number, not a pointer, and the numbers do not all follow one rule.

### Typed handles: render

A render resource handle is a one-member struct, `{ uint32_t bits }`, one struct type per kind —
`ke_mesh_handle`, `ke_texture_handle`, `ke_material_handle`, `ke_cubemap_handle`,
`ke_shadow_map_handle` (`src/c/render/kernel_engine/render/handles.h:23-27`) and `ke_ui_font_handle`
(`src/c/render/kernel_engine/render/ui/components.h:13-16`). Distinct struct types make passing a mesh
where a texture belongs a compile error in C; the managed projection keeps that with one
`readonly record struct` per kind it names — mesh, texture, material, shadow map, font
(`src/csharp/render/KernelEngine.Render.Abstractions/Handles.cs:3-32`).

`bits` packs a **20-bit index** in the low bits and a **12-bit generation** above it
(`KE_HANDLE_INDEX_BITS`, `KE_HANDLE_GENERATION_BITS`, `handles.h:11-12`). The lowest
generation a live handle carries is `1`, and `KE_HANDLE_NONE` is `0`, so a handle with all bits
zero is "none" and a component whose handle field was never written reads as none
(`handles.h:18-21`; `KE_MESH_NONE` etc., `:37-41`). A handle is valid when its `bits` differ from
`KE_HANDLE_NONE`. The header carries the constants only; the plugins that pack or unpack a handle share
`src/zig/render/common/handle.zig`.

The one implementation, the render service's slot map, repeats the packing constants in its own source
(`src/zig/render/service/src/slot_map.zig:5-24`) and enforces the rules the header implies:
`insert` returns none when the index would not fit in 20 bits; `remove` increments the slot's generation
modulo 4096 and skips `0`; `get` yields nothing for none, an out-of-range index, a free slot, or a
generation that does not match — a handle to a removed resource is refused, not aliased onto
whatever reused the slot (`:34-78`).

### Which identifiers use zero for "none"

| identifier | none / invalid | where |
|---|---|---|
| `ke_mesh_handle`, `ke_texture_handle`, `ke_material_handle`, `ke_cubemap_handle`, `ke_shadow_map_handle`, `ke_ui_font_handle` | `0` | `handles.h:21`; `ui/components.h:19` |
| `ke_entity` | `0` (`KE_ENTITY_INVALID`) | `src/c/ecs/kernel_engine/ecs/ecs.h:13-14` |
| `ke_query_id` | `0` | `ke_ecs.h:14-15` |
| `ke_audio_sound`, `ke_body_2d` | `0` | `audio.h:15-16`; `physics_2d.h:14-15` |
| `ke_script_type_id` | `0` | `script_host.h:35` |
| `ke_module_id`, `ke_system_id` | `0` is what a refused registration returns | `runtime.h:17-18`, `runtime.zig:423-427`, `:465-468` |
| `ke_resource_handle` | `UINT32_MAX` | `src/c/resource_cache/kernel_engine/resource_cache/resource_cache.h:13-15` |
| `ke_configuration_subscription` | `UINT32_MAX` | `src/c/configuration/kernel_engine/configuration/configuration.h:15` |
| `ke_gpu_buffer`, `ke_gpu_texture`, and the other 64-bit GPU ids | `UINT64_MAX` (`KE_GPU_INVALID_HANDLE`) | `gpu_device.h:15-16`; `gpu_enums.h:239` |
| `ke_component_id` | `KE_COMPONENT_INVALID` is `(ke_component_id)-1`, but `component_register` reports failure with `0` and every component entry point refuses `0` | `ecs.h:16-17`; `ke_ecs.h:58`; `ecs_flecs.zig:365`, `:414`, `:422` |
| signal ids | none: the first signal registered is id `0`, and a lookup that finds nothing returns `false` | `src/zig/framework/src/signal_bus.zig:107-111`, `:119-134` |

So "a zeroed value means none" holds for the render handles, entities, queries, sounds, bodies and
script types, and does **not** hold for resource handles, configuration subscriptions, GPU ids or
signals. Where two of these are bare integers, a value moved from one to the other is a valid value of both. `ke_ui_font_handle` has a second reserved value, `UINT32_MAX`
(`KE_UI_FONT_FAILED`), for a font a label asked for and the engine could not produce
(`ui/components.h:19-23`).
