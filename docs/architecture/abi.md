# How does a call cross the C ABI, and how does a failure come back?

This is a map of the boundary: what a caller holds, what a failure carries, and how a resource is
named. Layers and file placement are in [layers.md](layers.md). The members of each contract are
on the generated page of its header, under `src/c/`.

## The parts

| part | declared in | receives | hands on |
|---|---|---|---|
| contract struct | one header per contract in `src/c/<domain>/` | a call through a slot, with the struct as first argument | the result, or a failure through `ke_error` |
| owner | `ke_<name>_handle`, beside its contract, for example `ke_window_handle` | nothing | the borrowed contract pointer (`ref`) and the function that destroys it (`destroy`) |
| factory | the factory header in a plugin's `include/`, for example `ke_window_glfw_create` | a `_params` struct, such as `ke_window_glfw_params`, and an error output | an owner |
| error record | `ke_error` and `ke_error_type` in `kernel_engine/common/error.h` | `ke_error_set`, through `KE_ERROR_SET` and `KE_ERROR_WRAP` | the failing call's output, and `ke_error_last` |
| error library | `ke_common`, built from `src/zig/common/src/error.zig` | nothing | the eight generic error types, `ke_error_is`, `ke_error_fatal` |
| error helper | `Errors` in `src/zig/common/kerror.zig` | the plugin's own translated C namespace | the same records, for a plugin that does not link `ke_common` |
| managed translation | `NativeErrors` in `src/csharp/common` | a `ke_error` pointer | a .NET exception, or a `ke_error` written from one |

**A call goes through a pointer.** A caller holds a pointer to a contract struct and calls one of
its slots, handing the struct back as first argument. The only symbol resolved by name is the
factory.

**A factory returns an owner.** The owner is by value: `ref` is the contract pointer and
`destroy` takes it back. Everything else that needs the object receives the borrowed contract
pointer. A factory that fails returns an owner whose `ref` is null.

**A failure is an output and a sentinel.** A call that can fail takes `ke_error **out_error`
last. On failure the callee fills it and returns its sentinel (false, a null handle, an invalid
id); the caller checks the return. The record lives in per-thread storage, so a pointer to it
holds until later failures on the same thread overwrite it, and what must outlive that is copied.

**An error type is a node in a tree.** Each `ke_error_type` has a name and an optional parent. A
domain declares its types beside its API and points the parent at one of the eight generic
roots, `KE_ERROR_GENERAL` among them. `ke_error_is` matches a type by address or by name, and
walks the parents.

**The managed side maps by name.** `NativeErrors.FromNative` walks the type chain, looks each name up in
the generated table of exceptions, and falls back to a general one. The cause chain becomes the
inner exception, and the full type name is kept in the exception's `Data` under `TypeKey`.

**One call ends the process.** `ke_error_fatal` prints the chain and exits; the header reserves it
for a caller with nowhere left to send an error.

**Booleans are `ke_bool`.** In a slot or a struct that crosses the ABI, a boolean is `ke_bool`
(`kernel_engine/common/types.h`), not C `bool`.

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
`KE_HANDLE_INDEX_BITS` and `KE_HANDLE_GENERATION_BITS`; the plugins that pack and unpack share
`Handles` in `src/zig/render/common/handle.zig`.

## What the parts agree on without a contract

- The dotted names of the generic error types, "ke.error" and "ke.error.not_found" to
  "ke.error.already_exists", are written in `src/zig/common/src/error_types.zig`. The generated
  `NativeErrors.Kinds.g.cs` matches the same strings.
- The order of the `Kind` enum of `Errors` is the order of those names.
- The key "ke.error_type" under which `NativeErrors` stores the native type name.
