using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Optional, dev-only platform abstraction. Wraps a <c>ke_dev_platform*</c> created by
/// a backend plugin (e.g. <c>KernelEngine.DevPlatform.Win32</c>).
///
/// When this service is registered, the framework forwards thread names to the OS so
/// debuggers and profilers can identify them, and (in the future) installs crash handlers
/// and writes minidumps.
///
/// When NOT registered, all dev-only diagnostics degrade to no-op without affecting
/// engine behavior — appropriate for shipped builds on platforms without dev tooling
/// support (consoles, restricted mobile, WebGL).
/// </summary>
public sealed unsafe class DevPlatform : IDisposable
{
    private ke_dev_platform* _native;

    /// <summary>The underlying native pointer. Can be passed directly to APIs that accept it.</summary>
    internal ke_dev_platform* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>Wraps an already-created <c>ke_dev_platform*</c>. Takes ownership.</summary>
    public DevPlatform(ke_dev_platform* native) => _native = native;

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native == null) return;
        if (_native->destroy != null) _native->destroy(_native);
        _native = null;
    }
}
