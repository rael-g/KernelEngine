using KernelEngine.Audio;

namespace KernelEngine.Framework;

/// <summary>
/// Behavior half of the generated <see cref="AudioPlayer"/> node: turns the clip
/// path the scene declared into a loaded sound, and releases it when the node
/// goes away. Path and Volume come from the component the scene authored, applied
/// by the field table generated from the C header — so a clip declared in a scene
/// reaches this node the same way in every language.
/// </summary>
public partial class AudioPlayer
{
    private readonly IAudio _audio;

    private SoundHandle _handle = SoundHandle.None;

    public AudioPlayer(IAudio audio) : this() => _audio = audio;

    protected override void OnReady()
    {
        if (string.IsNullOrEmpty(Path)) return;
        _handle = _audio.LoadSound(System.IO.Path.Combine(System.AppContext.BaseDirectory, Path));
    }

    protected override void OnUnbind()
    {
        if (_handle == SoundHandle.None) return;
        _audio.UnloadSound(_handle);
        _handle = SoundHandle.None;
    }

    /// <summary>Plays the loaded clip at <see cref="Volume"/>, restarting it if already playing.</summary>
    public void Play() => _audio.Play(_handle, Volume);
}
