using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A loaded sound, owned by the framework. Wraps the kernel's <see cref="SoundHandle"/> so game
/// code never sees the raw kernel handle. Dispose to release backend memory.
/// </summary>
/// <remarks>
/// <para>
/// MVP scope (chapter 23 first slice): inline loads only. Each <see cref="Sound"/> is owned by its
/// creator (typically an <see cref="AudioPlayer"/> node or a one-off <see cref="IAudioService.Load"/>
/// call). Shared/cached sounds (the equivalent of <c>res://</c> for audio) come in a later slice
/// once the bus mixer and clip pool land.
/// </para>
/// <para>
/// Construction is private — callers go through <see cref="IAudioService.Load"/>, which keeps
/// the kernel-side <see cref="SoundHandle"/> off the public API.
/// </para>
/// </remarks>
public sealed class Sound : IDisposable
{
    private readonly IAudio _backend;
    private SoundHandle _handle;
    private bool _disposed;

    internal Sound(IAudio backend, SoundHandle handle)
    {
        _backend = backend;
        _handle = handle;
    }

    /// <summary>Engine-internal: the raw kernel handle, exposed only inside the framework.</summary>
    internal SoundHandle Handle => _handle;

    /// <summary>True until <see cref="Dispose"/> runs. Failed loads dispose immediately.</summary>
    public bool IsValid => !_disposed && _handle.IsValid;

    /// <summary>Releases the sound on the backend. Safe to call multiple times.</summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_handle.IsValid) _backend.UnloadSound(_handle);
        _handle = SoundHandle.None;
    }
}
