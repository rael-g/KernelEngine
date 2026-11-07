# KernelEngine

KernelEngine is a microkernel game engine: ABI-stable C contracts, Zig plugins behind them, and a
managed C# layer for game code. Every capability is a plugin behind a vtable contract, and a
plugin exports one factory per header. Because the contracts are plain C, any language that can
call C can reach the ECS, the renderer or the framework the same way.

## Layers

| layer | where | holds |
|---|---|---|
| 1, C contracts | `src/c/<domain>/kernel_engine/<domain>/` | vtable shapes, parameter structs, enums; headers only |
| 2, plugins | `src/zig/<domain>/<plugin>/` | every implementation, one shared library each |
| 3, C# bindings | `src/csharp/<domain>/*/Native/Generated/` | P/Invoke surface generated from the headers |
| 4, C# managed | `src/csharp/<domain>/KernelEngine.*/` | wrappers, framework, game code |

## Requirements

- Zig 0.16.
- .NET 10.

## Build and test

Native (Zig and vcpkg):

```bash
zig build --prefix build/native --global-cache-dir build/zig-global
zig build test --prefix build/native --global-cache-dir build/zig-global
```

Managed (.NET):

```bash
dotnet build
dotnet test KernelEngine.slnx
```

## Run a first example

The example game is Pong, under `examples/csharp/games/pong`:

```bash
dotnet run --project examples/csharp/games/pong
```

## Contributing

- Read [CLAUDE.md](https://github.com/rael-g/KernelEngine/blob/main/CLAUDE.md) for the build, the layer rules and the coding conventions.
- Work reaches `main` as described in [Git](docs/conventions/git.md).
- Commits follow Conventional Commits, one per logical task.
- Documents are written to [Documentation](docs/conventions/docs.md).
- `scripts/verify.cs` runs the gates that check the rules a machine can check.
