# Managed layer

This is a map: the seams between the C# wrappers and the native plugins, and how a game is
composed on top. Layers and placement are in layers.md; the failure record that crosses the C ABI
is in abi.md. How a wrapper works inside is on the generated page of its file.

## The parts

| part | declared as | receives | hands on |
|---|---|---|---|
| generated wrapper | one class per vtable, under `Generated/` | the owner struct a factory returned, or a borrowed pointer | managed methods over the vtable slots |
| native interface | one per domain, such as `INativeEcs`, `INativeIo` | nothing | the wrapper's pointer, as `Native` |
| result translation | the private `NativeResult` of each generated class | a `ke_result`, or a managed exception | the exception the manifest names for the code, or the code it stands for |
| SDK | `KernelEngineHost`, `AddKernelEngine` | how to open an assembly, and what to write into it | every instance made when it starts, keyed services over them, the runner on the calling thread |
| defaults | `DefaultProject`, `AddDefaultKernelEngine` | a project directory and a composition file | the parts of every default library and the composition the file holds |

## What ties the parts together

**A wrapper owns one pointer, and holds what it borrows.** An owned wrapper keeps its pointer in a
`NativeOwner`, a private `SafeHandle` the wrapper declares, whose release runs the factory's destroy
function. A wrapper made by a factory adds a reference to the `Owner` of every contract it was
given and drops it when it is destroyed, so disposing a dependency first only drops its own
reference: the native object goes when its last holder does, in whatever order they are disposed.
A wrapper made by `Borrow` has no owner and never destroys.

**A pointer crosses assemblies through an interface.** The wrapper implements `INativeEcs`
explicitly, so `Native` is not a member of the class. A consumer in another assembly names the
interface to read the pointer; no assembly grants another access to its internals.

**A managed handler is called back by a native thread.** The wrapper turns a delegate into a
function pointer marked `UnmanagedCallersOnly` and a context that is a `GCHandle`; the native
side calls it on whichever worker it picked.

**An exception does not cross the native frame.** A handler's exception is caught and either
written to the result code, queued on the wrapper, or held for the call that returns to
managed code. The call that observes the failure throws `InvalidOperationException` carrying
what was queued, or the exception the manifest names for the code.

**A game is composed by the assembly, not by the container.** The container holds the host and the
services over it: `AddKernelEngine` registers nothing native, only factories that ask the started host for
an instance by name, so asking before it started fails. Starting the host resolves the composition and creates
every instance; stopping it destroys them in the reverse order. A game registers its node types between
`Start` and `Run`, before the first tick opens the first scene. No engine part asks the container for a
dependency.

## What the parts agree on without a contract

- The `Native` property of `INativeEcs` is the only way the pointer leaves a wrapper.
