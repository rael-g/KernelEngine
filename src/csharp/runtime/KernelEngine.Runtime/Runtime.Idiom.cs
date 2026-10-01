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

/// <summary>
/// The part of <see cref="SystemCtx"/> that is not a slot: reaching the context a body was
/// handed from its pointer, and the command queue the context carries as a field.
/// </summary>
public unsafe partial class SystemCtx
{
    /// <summary>
    /// Wraps the context a system body was handed. The native side owns it and it means
    /// nothing once the body returns, so the result must not be kept past the call.
    /// </summary>
    /// <param name="ctx">The context pointer the runtime passed to the body.</param>
    public static SystemCtx Of(nint ctx) => Borrow((ke_system_ctx*)ctx);

    /// <summary>
    /// The queue this body records structural changes into, applied at the wave barrier.
    /// Every operation on it fails in the render phase, which may not change structure.
    /// </summary>
    public EcsCommands Commands => EcsCommands.Borrow(_native->commands);
}
