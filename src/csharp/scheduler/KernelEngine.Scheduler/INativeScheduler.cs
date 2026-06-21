using KernelEngine.Common.Native;

namespace KernelEngine.Scheduler;

/// <summary>
/// Exposes the raw native scheduler pointer. Implemented by the concrete
/// Scheduler type so that plugin adapters (e.g. AssetLoader) can pass the
/// pointer to native param structs without depending on a specific scheduler implementation.
/// </summary>
public unsafe interface INativeScheduler
{
    ke_scheduler* Native { get; }
}
