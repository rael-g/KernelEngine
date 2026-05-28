using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Thin wrapper that lifts the kernel's <see cref="IAudio"/> into the framework-shaped
/// <see cref="IAudioService"/>. Registered by <c>AddAudioFramework()</c>.
/// </summary>
internal sealed class AudioService(IAudio backend) : IAudioService
{
    public Sound Load(string path)
    {
        var handle = backend.LoadSound(path);
        return new Sound(backend, handle);
    }

    public void Play(Sound sound, float volume = 1.0f, bool loop = false)
    {
        if (sound is null) throw new ArgumentNullException(nameof(sound));
        if (!sound.IsValid) return;
        backend.Play(sound.Handle, volume, loop);
    }

    public void Stop(Sound sound)
    {
        if (sound is null) throw new ArgumentNullException(nameof(sound));
        if (!sound.IsValid) return;
        backend.Stop(sound.Handle);
    }

    public void SetMasterVolume(float volume) => backend.SetMasterVolume(volume);
}
