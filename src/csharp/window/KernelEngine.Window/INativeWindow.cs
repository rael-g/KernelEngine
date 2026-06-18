using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Exposes the raw native window pointer. Implemented by the concrete Window type
/// so that plugin adapters (e.g. BgfxRenderer) can pass the pointer to native
/// param structs without depending on a specific window implementation.
/// </summary>
public unsafe interface INativeWindow
{
    ke_window* Native { get; }
}
