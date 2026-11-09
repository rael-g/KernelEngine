using KernelEngine.Ecs;
using KernelEngine.Ecs.Native;
using KernelEngine.TaskPool;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// The one part of <see cref="Runtime"/> that is not a direct image of the C ABI: the
/// borrowed dependencies are taken as their managed wrappers rather than as the pointers
/// the ABI's own constructor wants. Everything else is generated in
/// <c>Generated/Runtime.g.cs</c>.
/// </summary>
public unsafe partial class Runtime : IRuntime
{
    /// <summary>
    /// Builds a runtime over borrowed ECS storage and a borrowed task pool, both kept alive while
    /// the runtime lives.
    /// </summary>
    public Runtime(INativeEcs ecs, INativeTaskPool taskPool)
        : this(NativeEcsOf(ecs), NativeTaskPoolOf(taskPool), Sixty())
    {
        Hold(ecs.Owner);
        Hold(taskPool.Owner);
    }

    /// <summary>
    /// Builds a runtime as the constructor above does, the runtime library logging to
    /// <paramref name="loggerFactory"/>.
    /// </summary>
    public Runtime(INativeEcs ecs, INativeTaskPool taskPool, Microsoft.Extensions.Logging.ILoggerFactory loggerFactory)
        : this(RoutingLog(ecs, loggerFactory), taskPool)
    {
    }

    private static readonly Native.ke_runtime_params* SixtyPerSecond = SixtyPerSecondParams();

    private static Native.ke_runtime_params* SixtyPerSecondParams()
    {
        var p = (Native.ke_runtime_params*)System.Runtime.InteropServices.NativeMemory.Alloc((nuint)sizeof(Native.ke_runtime_params));
        *p = new Native.ke_runtime_params { fixed_dt = 1.0f / 60.0f, fixed_dt_max_accum = 0.25f, max_systems_per_phase = 256 };
        return p;
    }

    private static Native.ke_runtime_params* Sixty() => SixtyPerSecond;

    private static INativeEcs RoutingLog(INativeEcs ecs, Microsoft.Extensions.Logging.ILoggerFactory loggerFactory)
    {
        ArgumentNullException.ThrowIfNull(loggerFactory);
        KernelEngine.Runtime.Native.NativeMethods.runtime_set_log_callback(KernelEngine.Logger.NativeLogging.Callback, KernelEngine.Logger.NativeLogging.ContextOf(loggerFactory));
        return ecs;
    }

    private static ke_ecs* NativeEcsOf(INativeEcs ecs)
    {
        ArgumentNullException.ThrowIfNull(ecs);
        return ecs.Native;
    }

    private static ke_task_pool* NativeTaskPoolOf(INativeTaskPool taskPool)
    {
        ArgumentNullException.ThrowIfNull(taskPool);
        return taskPool.Native;
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
