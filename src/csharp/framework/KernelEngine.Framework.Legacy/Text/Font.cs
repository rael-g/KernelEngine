using KernelEngine.Text;


namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A loaded font ready to render — owns its atlas <see cref="Texture"/> and a glyph lookup table.
/// Created via <c>Assets.LoadFontAsync</c>; passed to <see cref="Label"/> nodes for rendering.
/// Disposing the Font releases its atlas texture; cached fonts in <see cref="Assets"/> handle
/// ref-counting on top.
/// </summary>
public sealed class Font : IDisposable
{
    private readonly Dictionary<uint, GlyphMetrics> _glyphs;
    private bool _disposed;

    /// <summary>The atlas texture (RGBA8) that the UI shader samples for glyph coverage.</summary>
    public Texture Atlas { get; }

    /// <summary>Recommended line spacing for this font at its baked size (pixels).</summary>
    public float LineHeight { get; }

    /// <summary>Pixels above baseline to the top of the tallest glyph.</summary>
    public float Ascent { get; }

    internal Font(Texture atlas, GlyphMetrics[] glyphs, float lineHeight, float ascent)
    {
        Atlas      = atlas;
        LineHeight = lineHeight;
        Ascent     = ascent;
        _glyphs    = new Dictionary<uint, GlyphMetrics>(glyphs.Length);
        foreach (var g in glyphs) _glyphs[g.Codepoint] = g;
    }

    /// <summary>True when <paramref name="codepoint"/> was baked into this font's atlas.</summary>
    public bool TryGlyph(uint codepoint, out GlyphMetrics metrics) =>
        _glyphs.TryGetValue(codepoint, out metrics);

    /// <summary>Measures a string at this font's baked size (in pixels). Single-line only — newlines NYI.</summary>
    public float MeasureWidth(string text)
    {
        float w = 0f;
        for (int i = 0; i < text.Length; i++)
        {
            if (_glyphs.TryGetValue(text[i], out var g)) w += g.AdvanceX;
        }
        return w;
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Atlas.Dispose();
    }
}
