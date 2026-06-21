using KernelEngine.Common.Native;

namespace KernelEngine.Runtime;

/// <summary>
/// Exposes the raw native runtime pointer. Implemented by the concrete Runtime type
/// so that framework factories can pass the pointer to native param structs without
/// depending on a specific runtime implementation.
/// </summary>
public unsafe interface INativeRuntime
{
    ke_runtime* Native { get; }
}
