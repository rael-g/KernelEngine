using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Manages the OS window. Takes ownership of a <c>ke_window*</c> created by a plugin factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// </summary>
public sealed unsafe class Window : IDisposable
{
    private ke_window* _native;

    public ke_window* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>
    /// Wraps an already-created <c>ke_window*</c> and calls <c>on_initialize</c>.
    /// </summary>
    public Window(ke_window* native)
    {
        _native = native;
        KernelException.ThrowIfFailed(_native->on_initialize(_native));
    }

    /// <summary>Returns <see langword="true"/> when the user has requested the window to close.</summary>
    public bool ShouldClose() => _native->should_close(_native);

    /// <summary>Processes pending OS events. Call once per frame.</summary>
    public void PollEvents() =>
        KernelException.ThrowIfFailed(_native->poll_events(_native));

    /// <summary>Returns the current client area size in pixels.</summary>
    public (int Width, int Height) GetSize()
    {
        int w, h;
        KernelException.ThrowIfFailed(_native->get_size(_native, &w, &h));
        return (w, h);
    }

    /// <summary>Returns the platform-specific native window handle (HWND, X11 Window, etc.).</summary>
    public nint GetNativeHandle() => (nint)_native->get_native_handle(_native);

    public void Dispose()
    {
        if (_native != null)
        {
            _native->on_shutdown(_native);
            _native->destroy(_native);
            _native = null;
        }
    }
}
