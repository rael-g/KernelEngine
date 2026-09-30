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
(`src/zig/window/glfw/include/kernel_engine/window/glfw/glfw_window.h:34`). Parameters live in the
struct so a field can be added without changing the function's signature.

## How a failure comes back

A call that can fail takes `ke_error **out_error` as its last parameter. On failure the callee
records the error and returns its sentinel — `false`, a null handle, an invalid id. The caller
checks the return; `*out_error` is meaningful only after a failure.

There is no result-code type. `grep -rn ke_result src` finds nothing.

### What the error record holds

`ke_error` has `type`, `message`, `file`, `line` and `cause`
(`src/zig/common/include/kernel_engine/common/error.h:41`). It lives in per-thread storage:

- two slots per thread, so wrapping an error with `KE_ERROR_WRAP` keeps the inner one valid while
  the outer is built (`src/zig/common/src/error.zig:25`);
- the message is copied into the slot and truncated at 512 bytes, never allocated, so a failing path
  does not depend on the allocator (`error.zig:28`, `error.zig:65`).

A pointer to a `ke_error` is therefore valid until the next two failures **on the same thread**
(`error.h:38-40`). Copy what must outlive that.

### What an error's type is

`ke_error_type` is a node with a `name` and a `parent` (`error.h:33`). Types form a tree; a domain
declares its own beside its own API and points `parent` at a generic root
(`error.h:12-32`). `ke_error_is` walks from the error's type up through `parent`, comparing node
addresses (`error.zig:39-47`).

The eight generic roots are exported by `ke_common` (`error.zig:30-37`). A Zig plugin that cannot
link `ke_common` fills the error through `Errors(c).fail` in `src/zig/common/kerror.zig:84`, which
uses a set of type nodes of its own (`kerror.zig:64-67`).

The managed side matches by name, walking `Parent`
(`src/csharp/common/KernelEngine.Common/KernelErrorType.cs:31-37`).

### The one sanctioned way to end the process

`ke_error_fatal` prints the chain and terminates (`error.h:83-94`). It is called by a caller that has
an error and nowhere left to send it, never by engine code on its own initiative.

## Booleans

`ke_bool` is a `uint8_t` (`src/zig/common/include/kernel_engine/common/types.h:13`), which
exists because C `bool` is not blittable through P/Invoke (`types.h:11-12`).

## Doc tags

A `///` or `/** */` comment on a contract member may open with bracketed tags that state what the
signature cannot: `[out]` on a parameter the callee writes (`window.h:39`), `[borrowed,nullable]` on
a pointer the callee does not own and may receive as null (`glfw_window.h:25`). kabic reads them
(`src/csharp/kabic/Kabic.Frontend/DocParser.cs:9`) and projects them into each target language; a
tag that is not there is a fact no projection can recover.
