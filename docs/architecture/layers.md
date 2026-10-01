# How is the engine divided into layers, and where does each kind of file live?

Four layers. Each is a directory pattern, and a file's layer is decided by where it sits, not by
what it says about itself.

| layer | where | holds |
|---|---|---|
| 1 — contracts | `src/c/<domain>/kernel_engine/<domain>/*.h` | vtable shapes, parameter structs, enums |
| 2 — plugins | `src/zig/<domain>/<plugin>/` | every implementation, one shared library each |
| 3 — bindings | `src/csharp/<domain>/*/Native/Generated/` | P/Invoke surface generated from layers 1 and 2 |
| 4 — managed | `src/csharp/<domain>/KernelEngine.*/` | wrappers, framework, game code |

The list of domains is `ls src/c`. The list of plugins is `grep 'ctx.plugin("' build.zig`; a
plugin not declared there is not built.

## Layer 1 — a contract is a struct of function pointers

A contract is a C struct whose members are function pointers plus an opaque `void *handle`
(`ke_window`, `src/c/window/kernel_engine/window/window.h:16`). Callers never link against a symbol
to use it; they call through the pointer.

Ownership travels in a second struct of the shape `{ ref, destroy }`
(`ke_window_handle`, `window.h:43`): the factory returns the owner, and everything else that needs
the object receives the borrowed `ke_window *`.

`src/c/` contains no `.c`, `.zig` or build file — only headers
(`find src/c -type f ! -name '*.h'` prints nothing).

## Layer 2 — a plugin exports one factory and nothing else

A plugin is a directory with its own `build.zig`, compiled to one dynamic library
(`src/zig/window/glfw/build.zig:48-54`). The only symbol the rest of the engine may link to is the
factory, declared in the plugin's own `include/` and defined with `export fn`:

- declaration: `src/zig/window/glfw/include/kernel_engine/window/glfw/glfw_window.h:34`
- definition: `src/zig/window/glfw/src/window_glfw.zig:18`

The factory takes a `_params` struct and an `out_error`, and returns the layer-1 owner
(`ke_window_handle`). Everything behind it — the GLFW calls, the state struct — is unreachable
except through the vtable it returns.

A plugin is configured by the root build, not by itself: the root `build.zig` runs each plugin's
`zig build` with one shared `--prefix` so every library lands in one directory
(`build.zig:911-939`), and passes each include path as a `-D` option
(`src/zig/window/glfw/build.zig:9-15`). A plugin asks for exactly the domains it consumes, so a
domain it did not ask for is not on its include path.

### Source that plugins share

Behavior two plugins both need is not put in a contract header. It is a Zig source file the root build
hands to each consumer as a `-D<name>-src` option (`build.zig:57-61`), and the consumer imports it as a
module. `src/zig/common/` holds `kerror.zig`, `heap.zig` and `component_fields.zig`;
`src/zig/render/common/` holds `handle.zig`. A shared file that touches C types is a
function of the consumer's own `c` namespace, as in `@import("kerror").Errors(c)`, so the types it sees
are the consumer's own. These files carry no tests of their own: the plugins that import them test them.

### One allocator per plugin, and the leak check

Every plugin allocates from `heap.gpa` (`heap.zig`): a wrapper over a `DebugAllocator` in a Debug
build, which catches a double free or a free of the wrong length, and `smp_allocator` otherwise. The
factories take no allocator, and a block is freed by the plugin that allocated it; memory a plugin
hands out is released through that plugin's own `free_*` slot.

The allocator is never reset. The first allocation registers one `atexit` callback, and that callback
runs the leak check once, when the process or the library ends, logging every block still allocated
with the stack that allocated it. `heap.leaks()` runs the same check on demand and returns the count,
so a test can assert zero after it has destroyed what it created (`heap.expectNoLeaks`, which each plugin that can be created without a GPU, a window or a native host library does in its own file); a leak that no test asserts is
reported only at exit, not as a test failure. The asset loader for assimp keeps a tracking allocator
of its own and does not take part.

## Layer 3 — bindings are generated, never written

Each managed project has a `Native/` directory with an `.rsp` naming the headers to read, the
library to load and the output namespace
(`src/csharp/window/KernelEngine.Window.Glfw/Native/Glfw.rsp`). The generated
`[DllImport("ke_window_glfw", ... EntryPoint = "ke_window_glfw_create")]` is in
`.../Native/Generated/NativeMethods.cs:8`.

Two generators feed the layer and they are not interchangeable. ClangSharp produces the raw
struct-and-function surface from the headers. kabic (`src/csharp/kabic/`) produces the idiomatic
projection from the same headers' doc tags, and is driven by `scripts/api_domains.json`
(`scripts/regenerate_api.cs:23`). Both are run by `scripts/`; nothing under `Generated/` is ever
edited.

## Layer 4 — managed code reaches native code only through layer 3

The managed projects copy the plugin libraries from `build/native/lib` at build time
(`src/csharp/NativeDependencies.targets:51,56`). Managed code names no native symbol itself; it
calls the layer-3 surface, and game code composes the wrappers by dependency injection from its own
`Program.cs`.

## What decides which directory a new file goes in

- It declares what a caller may require of a whole class of implementations → `src/c/`.
- It implements one, or is the factory header that creates one → `src/zig/<domain>/<plugin>/`.
- A contract header never lives under `src/zig/`; a factory header never lives under `src/c/`.
- It is generated from either → `Generated/`, and is not edited.

Where a new file would have to cross these lines to work, the contract is wrong, not the line.
