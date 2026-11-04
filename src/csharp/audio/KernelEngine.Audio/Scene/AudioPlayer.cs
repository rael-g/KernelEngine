namespace KernelEngine.Framework;

/// <summary>
/// Behavior half of the generated <see cref="AudioPlayer"/> node. The clip the scene declared is
/// loaded, played and released by the native audio player system.
/// </summary>
public partial class AudioPlayer
{
    /// <summary>Plays the clip once from its start at <see cref="Volume"/> on the next update;
    /// does nothing when no clip is loaded.</summary>
    public void Play() => PlayRequested = true;
}
