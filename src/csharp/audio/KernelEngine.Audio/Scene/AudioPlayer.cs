using KernelEngine.Audio;

namespace KernelEngine.Framework;

/// <summary>
/// Behavior half of the generated <see cref="AudioPlayer"/> node: turns the clip
/// path the scene declared into a loaded sound, and releases it when the node
/// goes away. Path and Volume are generated from the C header, so they are typed,
/// defaulted, and visible to every language rather than being read out of an
/// untyped property bag here.
/// </summary>
public partial class AudioPlayer
{
    private readonly IAudio _audio;

    private SoundHandle _handle = SoundHandle.None;

    public AudioPlayer(IAudio audio) : this() => _audio = audio;

    protected override void OnReady()
    {
        // The scene's [entity.properties] block is still the wiring for a node's
        // own fields; the component block that would feed Path directly has no
        // registration home yet for this domain.
        if (TryGetProperties(out var props))
        {
            if (props.TryGetString("Path", out var declared) && !string.IsNullOrEmpty(declared))
                Path = declared!;
            if (props.TryGetFloat("Volume", out var volume) && volume > 0f)
                Volume = volume;
        }

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
