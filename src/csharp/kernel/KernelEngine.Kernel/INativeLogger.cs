using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native logger pointer. Implemented by the concrete Logger type
/// so that kernel-layer code (e.g. Allocator) and plugin adapters (e.g. Assimp,
/// StbImage) can access the pointer without depending on the Logger assembly.
/// </summary>
public unsafe interface INativeLogger
{
    ke_logger* Native { get; }
}
