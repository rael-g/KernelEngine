namespace KernelEngine.Text;

/// <summary>
/// CPU-side font data produced by an <see cref="IFontLoader"/>. Owns its atlas + metrics arrays
/// (managed memory — the loader copies out of the native buffer it allocated). Dispose is a no-op
/// today (managed GC handles the arrays); the type is <see cref="IDisposable"/> so callers can
/// <c>using</c>-wrap it and gain future-proofing if we ever pin / pool the atlas.
/// </summary>
public sealed class FontData : IDisposable
{
    /// <summary>RGBA8 atlas bytes (<see cref="AtlasWidth"/> × <see cref="AtlasHeight"/> × 4).</summary>
    public byte[] AtlasRgba { get; }
    public uint   AtlasWidth { get; }
    public uint   AtlasHeight { get; }

    /// <summary>One entry per baked glyph (UV + bearing + advance, in pixels at the font's size).</summary>
    public GlyphMetrics[] Glyphs { get; }

    /// <summary>Recommended line spacing in pixels (ascent + descent + line gap, scaled to the baked size).</summary>
    public float LineHeight { get; }

    /// <summary>Pixels above baseline to the top of the tallest glyph (used to align text by baseline vs top).</summary>
    public float Ascent { get; }

    public FontData(byte[] atlasRgba, uint atlasWidth, uint atlasHeight,
                    GlyphMetrics[] glyphs, float lineHeight, float ascent)
    {
        AtlasRgba   = atlasRgba;
        AtlasWidth  = atlasWidth;
        AtlasHeight = atlasHeight;
        Glyphs      = glyphs;
        LineHeight  = lineHeight;
        Ascent      = ascent;
    }

    public void Dispose() { /* nothing to release today; placeholder for future pooling */ }
}
