namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Framework-level audio facade. Game code talks to this — never to <c>IAudio</c> or
/// <c>SoundHandle</c> (kernel concerns). All methods accept managed <see cref="Sound"/>
/// instances; the underlying backend handle stays internal.
/// </summary>
/// <remarks>
/// MVP scope: load, play, stop, master volume. Bus mixer (Master/Music/SFX/UI/Ambience),
/// clip pool with weighted/round-robin selection, pitch/volume jitter, logical
/// <c>audio.Trigger(name)</c> from <c>.event</c> files, and spatial 3D playback are all
/// deferred to subsequent slices of chapter 23.
/// </remarks>
public interface IAudioService
{
    /// <summary>
    /// Loads a sound file from <paramref name="path"/>. Returns a <see cref="Sound"/> the caller
    /// owns and must dispose. Format detected by the backend (miniaudio handles WAV/FLAC/MP3/OGG).
    /// </summary>
    Sound Load(string path);

    /// <summary>Plays <paramref name="sound"/>. Restarts from the beginning if already playing.</summary>
    void Play(Sound sound, float volume = 1.0f, bool loop = false);

    /// <summary>Stops <paramref name="sound"/>. No-op when not playing.</summary>
    void Stop(Sound sound);

    /// <summary>Sets a global multiplier applied on top of per-play volumes (0..1).</summary>
    void SetMasterVolume(float volume);
}
