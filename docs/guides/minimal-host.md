# Start the engine from your own program

A host is a program that chooses the plugins, loads them and drives the loop. The smallest one
is `examples/csharp/00_runtime_minimal/Program.cs`; every passage below is quoted from it.

## Choose the parts

The engine has no default set of plugins. The host registers the ones it wants in a service
collection: a logger and a sink for it, an implementation of the ECS, one of the scheduler, the
runtime, and each module it wants loaded. Here the only module is the window.

[!code-csharp[](../../examples/csharp/00_runtime_minimal/Program.cs#compose)]

## Build them and load the modules

Building the provider creates the native objects. `LoadModules` then hands each registered
`IRuntimeModule` the runtime, in dependency order, so that it can register its components and
systems.

[!code-csharp[](../../examples/csharp/00_runtime_minimal/Program.cs#load)]

## Register a system

Game code reaches the loop by registering a system in a phase. This one runs once per tick in
the update phase and touches no component.

[!code-csharp[](../../examples/csharp/00_runtime_minimal/Program.cs#system)]

## Drive the loop

The host owns the loop. Each turn it lets the window read its events and asks the runtime for
one tick, giving it the time since the last one.

[!code-csharp[](../../examples/csharp/00_runtime_minimal/Program.cs#loop)]

## Run it

```bash
zig build --prefix build/native --global-cache-dir build/zig-global
dotnet run --project examples/csharp/00_runtime_minimal
```
