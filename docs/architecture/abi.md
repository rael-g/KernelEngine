# The C ABI

This is a map of the boundary: what a caller holds, what a failure carries, and how a resource is
named. Layers and file placement are in [layers.md](layers.md). The members of each contract are
on the generated page of its header, under `src/c/`.

## The parts

| part | declared in | receives | hands on |
|---|---|---|---|
| contract struct | one header per contract in `src/c/<domain>/` | a call through a slot, with the struct as first argument | a `ke_result`, and a value through a last `out_` parameter |
| owner | `ke_<name>_handle`, beside its contract, for example `ke_window_handle` | nothing | the borrowed contract pointer (`ref`) and the function that destroys it (`destroy`) |
| factory | the factory header in a plugin's `include/`, for example `ke_window_glfw_create` | a `_params` struct, such as `ke_window_glfw_config`, and the `out_` handle | `KE_OK` and an owner through the output |
| result code | `ke_result` in `kernel_engine/result/result.h` | nothing | `KE_OK`, or the code of the failure |
| result helper | `Result` in `src/zig/result/result.zig` | the plugin's own translated C namespace | `R.ok`, `R.code`, `R.check` and `R.Error`, the conversions between a Zig error and a code |
| managed translation | `NativeResults` in `src/csharp/result` | a `ke_result` | a .NET exception, or a `ke_result` written from one |

**A call goes through a pointer.** A caller holds a pointer to a contract struct and calls one of
its slots, handing the struct back as first argument. The only symbol resolved by name is the
factory.

**A factory returns an owner.** The owner is by value: `ref` is the contract pointer and
`destroy` takes it back. Everything else that needs the object receives the borrowed contract
pointer. A factory that fails returns an owner whose `ref` is null.

**A failure is a code.** A call that can fail returns `ke_result`: `KE_OK`, or the code of the failure.
A value the call produces is written through a last `out_` parameter, left zeroed on failure. The
reason is logged where it happens, and the caller checks the code; ignoring it is a compiler warning.

**A code belongs to a domain.** The domain sits in the high 16 bits and the number in the low, built
by `KE_RESULT_CODE`. The generic codes, `KE_RESULT_GENERAL` among them, are domain zero, and a code
the managed side does not know becomes the general exception.

**The managed side maps by code.** `NativeResults.FromCode` looks the code up in the generated table
of exceptions and falls back to a general one; `ToCode` goes the other way for a callback that threw.

**Booleans are C `bool`.** A slot or a struct that crosses the ABI takes C `bool`, one byte. It
reaches C# as a one-byte `bool` because every engine assembly disables runtime marshalling
(`src/csharp/DisableRuntimeMarshalling.props`); an assembly that marshalled it would read a
four-byte `BOOL`.

## How a resource is named

A resource is named by a number, and the number that means "none" differs per kind.

| identifier | none or invalid |
|---|---|
| render handles such as `ke_mesh_handle` and `ke_texture_handle` | `KE_HANDLE_NONE`, zero bits |
| `ke_ui_font_handle` | `KE_UI_FONT_NONE`; `KE_UI_FONT_FAILED` marks a font that could not be produced |
| `ke_entity` | `KE_ENTITY_INVALID`, zero |
| `ke_component_id` | `KE_COMPONENT_INVALID` |
| `ke_query_id` | `KE_QUERY_INVALID`, zero |
| `ke_audio_sound` | `KE_AUDIO_SOUND_INVALID`, zero |
| `ke_resource_handle` | `KE_RESOURCE_HANDLE_NONE` |
| configuration subscription | `KE_CONFIGURATION_SUBSCRIPTION_NONE` |
| GPU object ids | `KE_GPU_INVALID_HANDLE` |

A render handle is a one-member struct, one struct type per kind, so a mesh passed where a texture
belongs does not compile in C. Its bits pack an index and a generation, sized by
`KE_HANDLE_INDEX_BITS` and `KE_HANDLE_GENERATION_BITS`. Only the producers pack and unpack them:
the render service's `src/zig/render/service/src/slot_map.zig` and the ui pass's font table.

## What the parts agree on without a contract

- The numbers of the generic codes, written in `result.h`, and the table of exceptions generated from them.
