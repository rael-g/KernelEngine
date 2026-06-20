using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native world pointer. Implemented by the concrete World type
/// so that framework factories (e.g. SceneLoader) can pass the pointer to native
/// param structs without depending on specific framework internals.
/// </summary>
public unsafe interface INativeWorld
{
    ke_world* Native { get; }
}
