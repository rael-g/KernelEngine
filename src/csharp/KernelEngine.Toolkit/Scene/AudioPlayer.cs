using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Node that loads a single audio clip from a path declared in the scene file
/// and exposes <see cref="Play"/> for one-shot playback.
/// Scene-file properties: <c>Path</c> (string, relative to BaseDirectory),
/// <c>Volume</c> (float, 0..1, default 1.0).
/// </summary>
public class AudioPlayer : Node
{
    private readonly IAudio _audio;

    private SoundHandle _handle = SoundHandle.None;
    private float       _volume = 1f;

    public AudioPlayer(IAudio audio) => _audio = audio;

    protected internal override void OnBind(NodeWorld nodeWorld) { }

    protected internal override void OnReady()
    {
        if (!TryGetProperties(out var props)) return;

        if (props.TryGetString("Path", out var path) && !string.IsNullOrEmpty(path))
        {
            var full = System.IO.Path.Combine(System.AppContext.BaseDirectory, path!);
            _handle = _audio.LoadSound(full);
        }

        props.TryGetFloat("Volume", out _volume);
        if (_volume == 0f) _volume = 1f;
    }

    protected internal override void OnUnbind()
    {
        if (_handle != SoundHandle.None)
        {
            _audio.UnloadSound(_handle);
            _handle = SoundHandle.None;
        }
    }

    /// <summary>Plays the loaded clip at the configured volume.</summary>
    public void Play() => _audio.Play(_handle, _volume);
}
