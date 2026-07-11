using KernelEngine.Render;
using KernelEngine.Text;


namespace KernelEngine.Framework;

/// <summary>
/// A loaded font ready to render. Owns its GPU atlas <see cref="AtlasHandle"/>
/// and an in-memory glyph table built from the CPU-side font data the loader
/// produced. Create via <see cref="Load"/> from inside a scene setup callback
/// (render worker thread — GPU resource creation has thread affinity).
/// </summary>
public sealed class Font
{
    private readonly Dictionary<uint, GlyphMetrics> _glyphs;

    public TextureHandle AtlasHandle { get; }
    public float         LineHeight  { get; }
    public float         Ascent      { get; }

    private Font(TextureHandle atlas, GlyphMetrics[] glyphs, float lineHeight, float ascent)
    {
        AtlasHandle = atlas;
        LineHeight  = lineHeight;
        Ascent      = ascent;
        _glyphs     = new Dictionary<uint, GlyphMetrics>(glyphs.Length);
        foreach (var g in glyphs) _glyphs[g.Codepoint] = g;
    }

    /// <summary>
    /// Synchronously bakes <paramref name="path"/> at <paramref name="pixelSize"/>
    /// and uploads the atlas through <paramref name="resources"/>. MUST be called
    /// from the render worker because the texture upload is pinned there.
    /// </summary>
    public static Font Load(IRenderResources resources, IFontLoader loader, string path, float pixelSize,
                            uint atlasSize = 512, uint firstCodepoint = 32, uint codepointCount = 95)
    {
        using var data = loader.LoadFontAsync(path, pixelSize, atlasSize, firstCodepoint, codepointCount)
                               .GetAwaiter().GetResult();
        // Bake parameters are part of the key: the same font file at a different
        // size/range/atlas resolution is a genuinely different texture.
        var key = $"font:{path}:{pixelSize}:{atlasSize}:{firstCodepoint}:{codepointCount}";
        var atlas = resources.UploadTexture(key, data.AtlasWidth, data.AtlasHeight, data.AtlasRgba);
        return new Font(atlas, data.Glyphs, data.LineHeight, data.Ascent);
    }

    public bool TryGlyph(uint codepoint, out GlyphMetrics metrics) =>
        _glyphs.TryGetValue(codepoint, out metrics);

    /// <summary>Single-line pixel width of <paramref name="text"/> at this font's baked size.</summary>
    public float MeasureWidth(string text)
    {
        float w = 0f;
        for (int i = 0; i < text.Length; i++)
            if (_glyphs.TryGetValue(text[i], out var g)) w += g.AdvanceX;
        return w;
    }
}
