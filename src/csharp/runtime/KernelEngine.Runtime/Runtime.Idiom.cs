using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.Scheduler;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// The one part of <see cref="Runtime"/> that is not a direct image of the C ABI: the
/// borrowed dependencies are taken as their managed wrappers rather than as the pointers
/// the ABI's own constructor wants. Everything else is generated in
/// <c>Generated/Runtime.g.cs</c>.
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

}
