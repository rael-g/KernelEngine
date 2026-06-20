using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native input pointer. Implemented by the concrete Input type
/// so that plugins (e.g. GlfwWindow) can pass the pointer to native params structs
/// without depending on the Input assembly.
/// </summary>
public unsafe interface INativeInput
{
    ke_input* Native { get; }
}
