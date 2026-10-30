using KernelEngine.Audio;

namespace KernelEngine.Framework;

/// <summary>
/// Behavior half of the generated <see cref="AudioPlayer"/> node: turns the clip
/// path the scene declared into a loaded sound, and releases it when the node
/// goes away. Path and Volume come from the component the scene authored.
/// </summary>
public partial class AudioPlayer
{
    private readonly IAudio _audio;

    private uint? _sound;

    /// <summary>Creates a player that loads and plays its clip through <paramref name="audio"/>.</summary>
    public AudioPlayer(IAudio audio) => _audio = audio;

    protected override void OnReady()
    {
        if (string.IsNullOrEmpty(Path)) return;
        _sound = _audio.LoadSound(System.IO.Path.Combine(System.AppContext.BaseDirectory, Path));
    }

    protected override void OnUnbind()
    {
        if (_sound is not { } sound) return;
        _audio.UnloadSound(sound);
        _sound = null;
    }

    /// <summary>Plays the loaded clip at <see cref="Volume"/>, restarting it if already
    /// playing; does nothing when no clip was loaded.</summary>
    public void Play()
    {
        if (_sound is { } sound) _audio.Play(sound, Volume, false);
    }
}
