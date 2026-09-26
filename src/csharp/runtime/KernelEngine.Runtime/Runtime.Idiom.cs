using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// The parts of <see cref="Runtime"/> that are not a direct image of the C ABI: a body
/// written against the managed surface is handed the runtime rather than the raw context
/// pointer, and the borrowed dependencies are taken as their managed wrappers. Everything
/// mirroring the vtable 1:1 is generated in <c>Generated/Runtime.g.cs</c>.
/// </summary>
public sealed unsafe partial class Runtime : IRuntime
{
    /// <summary>
    /// Builds a runtime over borrowed ECS storage and a borrowed task scheduler.
    /// Only the pointers are taken: keeping the managed wrappers reachable is the
    /// caller's business, exactly as it is for whoever else borrows them.
    /// </summary>
    public Runtime(INativeEcs ecs, IScheduler taskScheduler)
        : this(NativeEcsOf(ecs), NativeSchedulerOf(taskScheduler), null)
    {
    }

    private static ke_ecs* NativeEcsOf(INativeEcs ecs)
    {
        ArgumentNullException.ThrowIfNull(ecs);
        return ecs.Native;
    }

    private static ke_scheduler* NativeSchedulerOf(IScheduler taskScheduler)
    {
        ArgumentNullException.ThrowIfNull(taskScheduler);
        return taskScheduler.Native;
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterModule(string name, Action<IRuntime> onLoad, Action<IRuntime>? onUnload = null)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        ArgumentNullException.ThrowIfNull(onLoad);

        return RegisterModule(name, rt => onLoad(rt),
            onUnload is null ? null : rt => onUnload(rt));
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                                 QueryDecl[]? queries = null,
                                 ComponentAccess[]? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemDeclared(name, phase, (_, dt) => execute(this, dt),
                               queries, accessList, pinnedThread, perEntity);
    }

    /// <inheritdoc />
    ulong IRuntime.RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, nint, float> execute,
                                 QueryDecl[]? queries = null,
                                 ComponentAccess[]? accessList = null,
                                 uint pinnedThread = 0,
                                 bool perEntity = false)
    {
        ArgumentNullException.ThrowIfNull(execute);
        return RegisterSystemDeclared(name, phase, (ctx, dt) => execute(this, ctx, dt),
                               queries, accessList, pinnedThread, perEntity);
    }

    private ulong RegisterSystemDeclared(string name, RuntimePhase phase, SystemExecute execute,
                                  QueryDecl[]? queries,
                                  ComponentAccess[]? accessList,
                                  uint pinnedThread,
                                  bool perEntity)
    {
        ArgumentException.ThrowIfNullOrEmpty(name);
        return RegisterSystemRaw(name, phase, queries ?? [], accessList ?? [], pinnedThread, perEntity, execute);
    }
}
