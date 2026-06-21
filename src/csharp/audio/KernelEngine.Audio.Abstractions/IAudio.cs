namespace KernelEngine.Audio;

/// <summary>
/// Managed mirror of the C kernel's <c>ke_audio</c> vtable — plays sounds loaded from disk.
/// Concrete implementations come from plugin libraries (e.g. <c>KernelEngine.Audio.MiniAudio</c>).
/// Methods are safe to call from any thread; backends marshal internally to their audio thread.
/// </summary>
public interface IAudio : IDisposable
{
    /// <summary>
    /// Loads a sound from <paramref name="path"/>. Format autodetected by the backend
    /// (miniaudio handles WAV / FLAC / MP3 / OGG out of the box).
    /// </summary>
    /// <returns>An opaque handle suitable for repeated playback, or <see cref="SoundHandle.None"/> on failure.</returns>
    SoundHandle LoadSound(string path);

    /// <summary>Releases a previously loaded sound. Safe on <see cref="SoundHandle.None"/>.</summary>
    void UnloadSound(SoundHandle sound);

    /// <summary>
    /// Plays <paramref name="sound"/> at <paramref name="volume"/> (0..1). When <paramref name="loop"/>
    /// is true the sound restarts on completion. Calling on an already-playing handle restarts playback
    /// from the start.
    /// </summary>
    void Play(SoundHandle sound, float volume = 1.0f, bool loop = false);

    /// <summary>Stops a currently playing sound. No-op when not playing.</summary>
    void Stop(SoundHandle sound);

    /// <summary>Sets a global volume multiplier applied on top of per-sound volumes (0..1).</summary>
    void SetMasterVolume(float volume);
}

/// <summary>Opaque per-backend handle for a loaded sound. Compare with <see cref="None"/> for validity.</summary>
public readonly record struct SoundHandle(uint Value)
{
    public static readonly SoundHandle None = new(0);
    public bool IsValid => Value != 0;
}
