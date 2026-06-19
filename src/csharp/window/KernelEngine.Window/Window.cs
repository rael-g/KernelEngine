using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Manages the OS window. Takes ownership of a <c>ke_window*</c> created by a service factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// </summary>
public sealed unsafe class Window : IWindow, INativeWindow
{
    private ke_window* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_window*, void> _destroy;

    ke_window* INativeWindow.Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>
    /// Wraps an owner <c>ke_window_handle</c> and calls <c>on_initialize</c>.
    /// </summary>
    public Window(ke_window_handle handle)
    {
        _native = handle.@ref;
        _destroy = handle.destroy;
        // In constructor we still throw because if initialization fails, the object is unusable.
        KernelException.ThrowIfFailed(_native->on_initialize(_native, null).ToManaged());
    }

    /// <summary>Returns <see langword="true"/> when the user has requested the window to close.</summary>
    public bool ShouldClose() => _native->should_close(_native) != 0;

    /// <summary>Processes pending OS events. Call once per frame.</summary>
    public Result PollEvents() => _native->poll_events(_native, null).Wrap();

    /// <summary>Returns the current client area size in pixels.</summary>
    public Result<(int Width, int Height)> GetSize()
    {
        int w, h;
        var res = _native->get_size(_native, &w, &h, null);
        return res.Wrap((w, h));
    }

    /// <summary>Returns the platform-specific native window handle (HWND, X11 Window, etc.).</summary>
    public nint GetNativeHandle() => (nint)_native->get_native_handle(_native);

    public void Dispose()
    {
        if (_native != null)
        {
            _native->on_shutdown(_native, null);
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
