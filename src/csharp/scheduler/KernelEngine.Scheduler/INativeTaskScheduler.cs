using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native task scheduler pointer. Implemented by the concrete
/// TaskScheduler type so that plugin adapters (e.g. AssetLoader) can pass the
/// pointer to native param structs without depending on a specific scheduler implementation.
/// </summary>
public unsafe interface INativeTaskScheduler
{
    ke_task_scheduler* Native { get; }
}
