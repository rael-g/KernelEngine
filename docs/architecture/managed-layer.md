# Managed layer

This is a map: the seams between the C# wrappers and the native plugins, and how a game is
composed on top. Layers and placement are in layers.md; the failure record that crosses the C ABI
is in abi.md. How a wrapper works inside is on the generated page of its file.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| generated wrapper | one class per vtable, under `Generated/` | the owner struct a factory returned, or a borrowed pointer | managed methods over the vtable slots |
| native interface | `INativeRuntime`, such as `INativeRuntime`, `INativeEcs` | nothing | the wrapper's pointer, as `Native` |
| idiom half | `<Name>.Idiom.cs`, a `partial` of the wrapper | managed dependencies | what a header cannot express |
| result translation | `NativeResults` | a `ke_result`, or a managed exception | the matching exception, or a `ke_result` |
| module | `IRuntimeModule` | `IRuntime` and `IServiceProvider` | components and systems registered into the runtime |
| module loader | `RuntimeStartup.LoadModules` | the modules in the container | `RegisterModule` calls in registration order |

## What ties the parts together

**A wrapper owns one pointer, and holds what it borrows.** An owned wrapper keeps its pointer in a
`NativeOwner`, a `SafeHandle` from `KernelEngine.Interop` whose release runs the factory's destroy
function. A wrapper made by a factory adds a reference to the `Owner` of every contract it was
given and drops it when it is destroyed, so disposing a dependency first only drops its own
reference: the native object goes when its last holder does, in whatever order they are disposed.
A wrapper made by `Borrow` has no owner and never destroys.

**A pointer crosses assemblies through an interface.** The wrapper implements `INativeRuntime`
explicitly, so `Native` is not a member of the class. A consumer in another assembly names the
interface to read the pointer; no assembly grants another access to its internals.

**A managed handler is called back by a native thread.** The wrapper turns a delegate into a
function pointer marked `UnmanagedCallersOnly` and a context that is a `GCHandle`; the native
side calls it on whichever worker it picked.

**An exception does not cross the native frame.** A handler's exception is caught and either
written to the result code, queued on the wrapper, or held for the call that returns to
managed code. The call that observes the failure throws `InvalidOperationException` carrying
what was queued, or the exception `NativeResults.FromCode` makes for the code.

**The task pool has its own channel.** The dispatch methods that are not generated return a
`Task`, which the body's failure faults.

**A module is the unit a game is loaded in.** `LoadModules` registers the `IRuntimeModule`
services in the order they were added, each with its `Name`; a module's `OnLoad` has run when
`RegisterModule` returns. A module depends on no other: what one needs from another is a service
the container creates on first use, and work that needs every module loaded runs in the startup
phase. The host calls `UnloadModules` when its loop ends, while every service a module's
`OnUnload` uses is alive; the container then disposes the services in the reverse of their
creation, and the runtime, created before what borrows it, last.

## What the parts agree on without a contract

- The `Native` property of `INativeRuntime` is the only way the pointer leaves a wrapper.
