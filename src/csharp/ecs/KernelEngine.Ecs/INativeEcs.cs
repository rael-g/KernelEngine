using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native ECS pointer. Implemented by ECS plugins (e.g. FlecsEcs)
/// so that runtime and framework factories can pass the pointer to native param
/// structs without depending on a specific ECS implementation.
/// </summary>
public unsafe interface INativeEcs
{
    ke_ecs* Native { get; }
}
