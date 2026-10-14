# How does the managed layer meet the native one?

This is a map: the seams between the C# wrappers and the native plugins, and how a game is
composed on top. Layers and placement are in layers.md; the failure record that crosses the C ABI
is in abi.md. How a wrapper works inside is on the generated page of its file.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| generated wrapper | one class per vtable, under `Generated/` | the owner struct a factory returned, or a borrowed pointer | managed methods over the vtable slots |
| native interface | `INative<Domain>`, such as `INativeLogger`, `INativeRuntime`, `INativeEcs` | nothing | the wrapper's pointer, as `Native` |
| idiom half | `<Name>.Idiom.cs`, a `partial` of the wrapper | managed dependencies | what a header cannot express |
| error translation | `NativeErrors` | a native error, or a managed exception | the matching exception, or a native error |
| module | `IRuntimeModule` | `IRuntime` and `IServiceProvider` | components and systems registered into the runtime |
| module loader | `RuntimeStartup.LoadModules` | the modules in the container | `RegisterModule` calls in dependency order |

## What ties the parts together

**A wrapper owns one pointer.** It keeps the pointer and the factory's destroy function, disposes
an owned wrapper by calling it, and a wrapper made by `Borrow` never destroys.

**A pointer crosses assemblies through an interface.** The wrapper implements `INative<Domain>`
explicitly, so `Native` is not a member of the class. A consumer in another assembly names the
interface to read the pointer; no assembly grants another access to its internals.

**A managed handler is called back by a native thread.** The wrapper turns a delegate into a
function pointer marked `UnmanagedCallersOnly` and a context that is a `GCHandle`; the native
side calls it on whichever worker it picked.

**An exception does not cross the native frame.** A handler's exception is caught and either
written to the native error, queued on the wrapper, or held for the call that returns to
managed code. The call that observes the failure throws `InvalidOperationException` carrying
what was queued, or the exception `NativeErrors.FromNative` makes for the native error.

**The scheduler has its own channel.** The dispatch methods that are not generated return a
`Task`, except `DispatchPinned`, whose failures are raised through
`Scheduler.UnobservedDispatchFailure`.

**A module is the unit a game is loaded in.** `LoadModules` sorts the `IRuntimeModule` services
by their `Dependencies` over the order they were added, and registers each with its `Name`; a
module's `OnLoad` has run when `RegisterModule` returns. A missing dependency or a cycle throws
before any module loads.

## What the parts agree on without a contract

- A module's `Dependencies` are concrete module types, matched by `GetType()`; the native
  runtime sees only the sorted order and the name.
- The `Native` property of `INative<Domain>` is the only way the pointer leaves a wrapper.
