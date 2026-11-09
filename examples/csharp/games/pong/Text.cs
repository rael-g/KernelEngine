using KernelEngine.Audio.Native;
using KernelEngine.Framework;
using KernelEngine.Render;

namespace Pong;

/// <summary>The text a label shows and the file a sound plays.</summary>
static class Text
{
    /// <summary>Makes <paramref name="label"/> show <paramref name="text"/>.</summary>
    public static void Show(ref LabelComponent label, string text) => label.TextText = text;

    /// <summary>The text a NUL-terminated buffer of UTF-8 holds.</summary>
    public static string Of(ReadOnlySpan<byte> bytes)
    {
        var end = bytes.IndexOf((byte)0);
        return System.Text.Encoding.UTF8.GetString(end < 0 ? bytes : bytes[..end]);
    }

    /// <summary>Points <paramref name="sound"/> at the file <paramref name="path"/>.</summary>
    public static void Play(ref SoundComponent sound, string path) => sound.PathText = path;
}
