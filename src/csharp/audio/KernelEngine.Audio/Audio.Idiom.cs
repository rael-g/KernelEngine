namespace KernelEngine.Audio;

/// <summary>
/// The parts of <see cref="Audio"/> that express the native surface in C# terms
/// rather than mirroring it: the <see cref="SoundHandle"/> value type wrapping a
/// bare <c>uint</c> id, and the "invalid handle is a silent no-op" policy the
/// managed contract promises but the ABI does not. Everything that is a direct
/// image of the C ABI is generated in <c>Generated/Audio.g.cs</c>.
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
