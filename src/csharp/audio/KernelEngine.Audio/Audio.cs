using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over a C kernel <c>ke_audio*</c>. Constructed by audio plugins (e.g.
/// <c>AddMiniAudio()</c>) and registered as <see cref="IAudio"/> for game-code consumption.
/// </summary>
public sealed unsafe class Audio : IAudio
{
    private ke_audio* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_audio*, void> _destroy;

    public Audio(ke_audio_handle handle)
    {
        if (handle.@ref == null) throw new ArgumentNullException(nameof(handle));
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    public SoundHandle LoadSound(string path)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        var ptr = Marshal.StringToHGlobalAnsi(path);
        try
        {
            uint id = _native->load_sound(_native, (sbyte*)ptr, null);
            return id != 0 ? new SoundHandle(id) : SoundHandle.None;
        }
        finally { Marshal.FreeHGlobal(ptr); }
    }

    public void UnloadSound(SoundHandle sound)
    {
        if (_native == null || !sound.IsValid) return;
        _native->unload_sound(_native, sound.Value);
    }

    public void Play(SoundHandle sound, float volume = 1.0f, bool loop = false)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        if (!sound.IsValid) return;
        _native->play(_native, sound.Value, volume, (byte)(loop ? 1 : 0), null);
    }

    public void Stop(SoundHandle sound)
    {
        if (_native == null || !sound.IsValid) return;
        _native->stop(_native, sound.Value);
    }

    public void SetMasterVolume(float volume)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->set_master_volume(_native, volume);
    }

    public void Dispose()
    {
        if (_native != null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
