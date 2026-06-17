namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A node that owns and plays a single <see cref="Sound"/>. Declarative analog to "drop an
/// <see cref="IAudioService"/>.Play call somewhere in game code" — usable in scene files (eventually)
/// and inspectable in the tree.
/// </summary>
/// <remarks>
/// <para>
/// Set <see cref="Path"/> in code (or scene properties, when scene files learn about
/// <see cref="AudioPlayer"/>); the node loads its <see cref="Sound"/> in <see cref="Start"/> via the
/// framework <see cref="IAudioService"/>. The loaded sound is disposed when the node leaves the
/// tree.
/// </para>
/// <para>
/// Call <see cref="Play"/> / <see cref="Stop"/> to drive playback. <see cref="AutoPlay"/> fires
/// once in <see cref="Start"/> for ambient/background tracks.
/// </para>
/// </remarks>
public class AudioPlayer(IAudioService audio) : Node, IDisposable
{
    private Sound? _sound;

    /// <summary>Path passed to <see cref="IAudioService.Load"/> at <see cref="Start"/>.</summary>
    public string? Path { get; set; }

    /// <summary>Per-play volume in [0, 1].</summary>
    public float Volume { get; set; } = 1.0f;

    /// <summary>When true, playback restarts on completion.</summary>
    public bool Loop { get; set; }

    /// <summary>When true, calls <see cref="Play"/> automatically at <see cref="Start"/>.</summary>
    public bool AutoPlay { get; set; }

    /// <summary>The loaded sound. Null until <see cref="Start"/> has run with a non-null <see cref="Path"/>.</summary>
    public Sound? Sound => _sound;

    protected override void Start()
    {
        base.Start();

        // Phase 5.3 of ECS-pure nodes: read scene-authored values from the
        // scene_properties bag. Falls back to the current field value, so the
        // legacy [[node]] path (NodeTypeRegistrar.ApplyProperty already set
        // the fields via reflection) and the new [[entity]] path (loader
        // wrote the bag, fields still default) both produce the same result.
        Path     = Properties.GetString("Path",     Path);
        Volume   = Properties.GetFloat ("Volume",   Volume);
        Loop     = Properties.GetBool  ("Loop",     Loop);
        AutoPlay = Properties.GetBool  ("AutoPlay", AutoPlay);

        if (!string.IsNullOrEmpty(Path))
        {
            var resolved = System.IO.Path.IsPathRooted(Path)
                ? Path
                : System.IO.Path.Combine(AppContext.BaseDirectory, Path);
            _sound = audio.Load(resolved);
        }
        if (AutoPlay) Play();
    }

    /// <summary>Plays the loaded sound. No-op when <see cref="Sound"/> hasn't loaded yet.</summary>
    public void Play()
    {
        if (_sound is null || !_sound.IsValid) return;
        audio.Play(_sound, Volume, Loop);
    }

    /// <summary>Stops the loaded sound. No-op when nothing is playing.</summary>
    public void Stop()
    {
        if (_sound is null || !_sound.IsValid) return;
        audio.Stop(_sound);
    }

    /// <summary>Disposes the owned sound. Called automatically when the node is destroyed.</summary>
    public void Dispose()
    {
        _sound?.Dispose();
        _sound = null;
    }
}
