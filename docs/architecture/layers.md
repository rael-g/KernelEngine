# How is the engine divided into layers, and where does each kind of file live?

This is a map of the four layers and of the files that cross them. How the boundary behaves is in
[abi.md](abi.md).

## The layers

| layer | where | holds |
|---|---|---|
| 1, contracts | `src/c/<domain>/kernel_engine/<domain>/*.h` | vtable shapes, parameter structs, enums; headers only |
| 2, plugins | `src/zig/<domain>/<plugin>/` | every implementation, one shared library each |
| 3, bindings | `src/csharp/<domain>/*/Native/Generated/` | P/Invoke surface generated from layers 1 and 2 |
| 4, managed | `src/csharp/<domain>/KernelEngine.*/` | wrappers, framework, game code |

A file's layer is decided by where it sits. The domains are `ls src/c`; the plugins are the
`ctx.member("` calls of the root `build.zig`, and a plugin not declared there is not built.

**A plugin is a directory with its own `build.zig`.** It compiles to one dynamic library
installed under `lib/`. Its public surface is a factory header under `include/`, defined by an
`export fn`; everything behind it is reachable only through the vtable the factory returns.

**The root build configures every plugin.** The root `build.zig` makes each plugin a dependency
and hands it, as `-D` options, the include directory of each domain it consumes, so a domain a
plugin did not ask for is not on its include path. All libraries are installed under the one
`--prefix` given to the root build.

**Layer 3 is generated from the headers.** ClangSharp produces the raw struct and function
surface; kabic (`src/csharp/kabic/`) produces the idiomatic projection from the doc tags of the
same headers, driven by `scripts/api_domains.json`. Neither output is edited by hand.

**Layer 4 reaches native code through layer 3.** The managed projects copy the plugin libraries
from `build/native/lib` (`NativeDependencies.targets`), and game code composes the wrappers by
dependency injection from its own `Program.cs`.

## Source the plugins share

Behavior two plugins both need is a Zig file the root build passes to each consumer as an option
named after the file, and the consumer imports it by that name.

| file | option | gives |
|---|---|---|
| `src/zig/common/heap.zig` | "heap-src" | `gpa`, the allocator of every plugin, with `leaks` and `expectNoLeaks` |
| `src/zig/common/kerror.zig` | "kerror-src" | `Errors`, the error helper of a plugin, and `_DllMainCRTStartup` |
| `src/zig/common/component_fields.zig` | "component-fields-src" | `Fields`, which writes a variant into a component |
| `src/zig/common/stubs.zig` | "stubs-src" | `Stubs`, fakes of device, target, render service, runtime, ecs and world for a plugin's tests |
| `src/zig/render/common/handle.zig` | | `Handles`, the packing of render handles |

A shared file that touches C types is a function of the importing plugin's own translated C
namespace, as in `Errors(c)`. The error library `ke_common` is a plugin of its own
(`src/zig/common/build.zig`) and a plugin that links it gets the generic error types from it.

## What decides which directory a file goes in

- What a caller may require of a whole class of implementations goes in `src/c/`.
- An implementation, or the factory header that creates it, goes in `src/zig/<domain>/<plugin>/`.
- A contract header never lives under `src/zig/`, and a factory header never under `src/c/`.
- Anything generated goes in `Generated/` and is not edited.

## What the parts agree on without a contract

- The option names of the table above, between the root `build.zig` and each plugin's `build.zig`.
- The `ke-lib-dir` option, the directory that holds the `ke_common` library a plugin links.
- The name of a plugin library, between its `build.zig` and the `bindings` entry of
  `scripts/api_domains.json` that names the library to load.
