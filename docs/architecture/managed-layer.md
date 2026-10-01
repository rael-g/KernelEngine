# How does the managed layer meet the native one?

Managed code reaches native code through generated wrappers, and native code reaches managed code
through callbacks that run on native threads. This document is what happens at those two seams, and
how game code is composed on top of them. Layers and file placement are in [layers.md](layers.md);
the failure record that crosses the C ABI is in [abi.md](abi.md#how-a-failure-comes-back).

## A wrapper owns one pointer

kabic generates one class per vtable from the contract header, into `Generated/<Name>.g.cs`
(`scripts/generate_csharp.cs:82-90`). `Runtime` is the pattern
(`src/csharp/runtime/KernelEngine.Runtime/Generated/Runtime.g.cs`):

- the pointer is a **private** field, `_native`, with the factory's `destroy` slot beside it
  (`Runtime.g.cs:23-25`);
- the constructor takes the factory's owner struct and keeps `ref` and `destroy`; `Borrow(ptr)` wraps
  a pointer someone else owns and never destroys it (`:90-98`);
- `Dispose` calls `destroy` for an owned wrapper only (`:285-308`);
- the parts a header cannot express are hand-written in a `partial` beside it, `Runtime.Idiom.cs`,
  which takes the borrowed dependencies as managed wrappers rather than pointers.

## How a pointer crosses assemblies

No assembly grants another access to its internals. `grep -rn InternalsVisibleTo src tests examples scripts`
finds one hit, a doc comment (`src/csharp/common/KernelEngine.Common/KernelError.cs:44`). What a
wrapper offers instead is a public interface per domain, declared in the same generated file:

```csharp
public unsafe interface INativeRuntime { ke_runtime* Native { get; } }
```

(`Runtime.g.cs:15-18`). The class implements it **explicitly**,
`ke_runtime* INativeRuntime.Native => Handle` (`:78`), so `Native` is not a member of `Runtime`: it
does not appear on the class, and a caller must name the interface to get the pointer. Another assembly
that borrows the object does exactly that — `Runtime` takes `INativeEcs` and reads `ecs.Native`
(`Runtime.Idiom.cs:19-35`), `World` casts `((INativeWorld)this).Native` (`World.Idiom.cs:46`),
`FrameworkModule` builds the native world from `INativeEcs` and `INativeRuntime`
(`Modules/FrameworkModule.cs:61-84`).

The interface is public, and `Native` is a plain pointer, so any holder of the object can cast to it:
the mechanism keeps the pointer off the class's own surface, not out of reach.
`grep -rn 'interface INative' src/csharp` lists them. The same constraint is why
`KernelError.FromNative` and `KernelError.ToNative` are `public` (`KernelError.cs:46`, `:80`).

A node type's members follow the same rule from the other side: `Node`'s hooks are
`protected internal`, so a node declared in another assembly cannot override an `internal` member.
The generator emits `protected` for such a class and `protected internal` only when the class and
`Node` are in one assembly (`NodePropertyGenerator.cs:70-74`).

## A managed handler on a native thread

A system body, a module hook or a scene factory is a managed delegate that a native thread calls
later. The generated wrapper turns it into a C function pointer and a context pointer:

1. a closure object holds the delegate and the owning wrapper, and a `GCHandle` over it is the
   context (`GCHandle.Alloc(new RegisterSystemClosures { Owner = this, Execute = execute })`,
   `Runtime.g.cs:201`). The handle keeps the object alive and in place for as long as native code may
   call back; `Runtime` keeps one per registration, keyed by the id the native call returned
   (`_retainedExecute[result]`, `:229`; `_retainedUserData[result]`, `:134`) and frees them in
   `Dispose` (`:285-300`);
2. the function pointer is a `static` method marked `[UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]`
   — the *trampoline* — whose first act is to recover the closure from the context
   (`RegisterSystemExecuteTrampoline`, `:244-262`). It runs on whichever worker the engine picked
   ([threading.md](threading.md#where-an-ordinary-system-body-runs)), so state a body needs per thread
   is `[ThreadStatic]`: the running system's context is
   (`ScriptHost._systemCtx`, `Scene/ScriptHost.Idiom.cs:57-81`);
3. the system body receives the context as an opaque `nint` and passes it back to the entry points that
   take one (`SystemExecute(nint ctx, float dt)`,
   `src/csharp/runtime/KernelEngine.Runtime.Abstractions/Generated/IRuntime.g.cs:19`).

Which slots become trampolines, and how, is declared by tags in the header, not chosen by the
generator: `[closure:user_data]` names the context lane, `[retained:return]` says the handler outlives
the call, `[teardown]` marks a hook with no error lane (`src/c/runtime/kernel_engine/runtime/runtime.h:75-80`;
`CSharpBackend.cs:1476-1612`).

### What a handler's exception does

An exception cannot unwind through native frames, so a trampoline catches everything. What it does
next depends on the handler's shape:

| handler | where the exception goes |
|---|---|
| has an error lane and outlives the registering call (system `execute`, scene script factory) | enqueued on the wrapper's `_callbackFailures`, **and** written to the native error lane as a message with no type; the native side returns failure (`Runtime.g.cs:253-261`, `SceneLoader.g.cs:135-152`) |
| has an error lane and runs inside the registering call (module `on_load`) | written to the native error lane only; the call that registered it throws (`Runtime.g.cs:148-160`, `:119-132`) |
| has no error lane (`on_unload`, a per-call event callback) | parked in a `[ThreadStatic]` slot, first one wins; rethrown by the call once the native stack has unwound (`Runtime.g.cs:167-178`, `:298-307`) |

`KernelError.ToNative` copies the **message**, prefixed with the context name, into the native record and sets no type
(`KernelError.cs:80-88`), so only the message survives that lane. A native caller that needs a type
substitutes one: the runtime turns an untyped failure of a system body into the generic type and
raises it on the tick thread with the system's name as its message
([runtime.md](runtime.md#how-a-failure-in-a-body-reaches-the-caller)).

The managed call that observes the failure is where the original exception comes back. `Tick`,
`Flush` and `SceneLoader.Load` check the native return, and when the queue is non-empty they throw
`InvalidOperationException("A handler registered with this provider threw")` carrying the exception
(or an `AggregateException` of all of them) in place of the native error
(`Runtime.g.cs:66-73`, `:266-282`; `SceneLoader.g.cs:87-98`). A failure of the native call itself, with
an empty queue, throws `KernelError`. The queue is read and emptied on every such call, so a failure
survives until some call asks.

The two scheduler entry points that are not generated have their own channel
(`Scheduler.Idiom.cs`). `Dispatch(Action)` carries the exception in a job object and faults the returned
`Task` (`:64-82`, `:121-139`); `Dispatch<T>` catches it in its own wrapper and sets it on the
`TaskCompletionSource` (`:84-95`). `DispatchPinned` has no result to fault; the exception is raised
through the static event `Scheduler.UnobservedDispatchFailure` (`:22-41`, `:49`) and is lost if
nothing subscribes. A module that must know its pinned work finished blocks on its own
`ManualResetEventSlim` and carries the exception itself
(`Modules/SceneNodesModule.cs:175-184`, `Modules/SceneRouterModule.cs:56-70`).

## Composing a game: `IRuntimeModule`

A module is the unit game and engine code are loaded in. `IRuntimeModule`
(`src/csharp/runtime/KernelEngine.Runtime.Abstractions/IRuntimeModule.cs`) has five members:

| member | when it runs |
|---|---|
| `Name` | read by `LoadModules` as the name passed to `RegisterModule`; defaults to the type's name (`RuntimeStartup.cs:30-32`, `IRuntimeModule.cs`) |
| `Configure(IServiceCollection)` | immediately, inside `services.Add<IRuntimeModule>(instance)` — before the provider exists (`ServiceCollectionExtensions.cs:45-52`) |
| `Dependencies` | read once, by `LoadModules`, as the types of the modules that must load first |
| `OnLoad(IRuntime, IServiceProvider)` | once, inside `RegisterModule`, on the thread that called `LoadModules` |
| `OnUnload(IRuntime, IServiceProvider)` | when the runtime is disposed, on the disposing thread |

`Add<TContract>(instance)` is `AddSingleton` plus the `Configure` call when the instance is a module.
`LoadModules` (`RuntimeStartup.cs:25-36`) gets every `IRuntimeModule` from the provider, sorts them,
and calls `runtime.RegisterModule(name, onLoad, onUnload)` for each, so a module's `OnLoad` has run by the
time `RegisterModule` returns (native `register_module` calls `on_load` synchronously,
`src/zig/runtime/src/runtime.zig:451`).

### Load order

`TopoSort` (`RuntimeStartup.cs:38-66`) is a depth-first walk over the modules **in registration
order**, visiting each one's `Dependencies` first. Consequences:

- Two modules with no dependency path between them load in the order they were added. A module that
  needs another's `OnLoad` to have run must name it in `Dependencies`, or be added after it.
- A dependency is a concrete module **type**, matched by `GetType()`; one that was not added, or a
  cycle, throws `InvalidOperationException` (`:49-50`, `:55-57`). Two modules of one type throw
  from `ToDictionary` (`:40`). All of that happens before the first module loads.
- `Dependencies` and the sort exist only here. The C contract's module params are `name`, `user_data`
  and the two hooks (`runtime.h:68-81`); the native runtime sees modules in the sorted order and nothing
  else.

Unload is the native runtime's reverse order of that same list ([runtime.md](runtime.md#modules)).
A module whose `OnLoad` throws is refused natively: the exception's message becomes a `KernelError`
thrown from `RegisterModule` (`Runtime.g.cs:128-131`), the modules before it stay loaded, and the
refused module's `OnUnload` is never called.
