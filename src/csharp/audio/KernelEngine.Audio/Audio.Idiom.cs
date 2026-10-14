namespace KernelEngine.Audio;

/// <summary>
/// The audio backend over <c>ke_audio</c>, exposed through <see cref="SoundHandle"/>. A call given
/// <see cref="SoundHandle.None"/> does nothing.
/// </summary>
public unsafe partial class Audio : IAudio
{
    /// <inheritdoc/>
    SoundHandle IAudio.LoadSound(string path)
    {
        var id = LoadSound(path);
        return id != 0 ? new SoundHandle(id) : SoundHandle.None;
    }

    /// <inheritdoc/>
    public void UnloadSound(SoundHandle sound)
    {
        if (sound.IsValid) UnloadSound(sound.Value);
    }

    /// <inheritdoc/>
    public void Play(SoundHandle sound, float volume = 1.0f, bool loop = false)
    {
        if (sound.IsValid) Play(sound.Value, volume, loop);
    }

    /// <inheritdoc/>
    public void Stop(SoundHandle sound)
    {
        if (sound.IsValid) Stop(sound.Value);
    }
}
