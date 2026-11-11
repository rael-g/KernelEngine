using KernelEngine.Audio;
using KernelEngine.Audio.Native;
using KernelEngine.Framework.Nodes;

namespace Pong;

/// <summary>The sounds Pong plays.</summary>
static class Sounds
{
    /// <summary>A sound node's component that plays <paramref name="path"/> once at <paramref name="volume"/> and is removed when it ends.</summary>
    public static SoundComponent Once(string path, float volume)
    {
        var sound = EngineNodeTypes.SoundNodeInitial;
        sound.Path = path;
        sound.Volume = volume;
        sound.Playing = true;
        sound.Release = SoundRelease.WhenDone;
        return sound;
    }
}
