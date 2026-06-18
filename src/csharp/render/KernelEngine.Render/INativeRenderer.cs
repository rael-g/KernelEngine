using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native renderer pointer. Implemented by the concrete Renderer type
/// so that plugin adapters can pass the pointer to native param structs without
/// depending on a specific renderer implementation.
/// </summary>
public unsafe interface INativeRenderer
{
    ke_render* Native { get; }
}
