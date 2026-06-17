using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A loaded font ready to render. Owns its GPU atlas <see cref="AtlasHandle"/>
/// and an in-memory glyph table built from the CPU-side font data the loader
/// produced. Create via <see cref="Load"/> from inside a SceneModule callback
/// (render worker thread).
/// </summary>
public sealed class Font : IDisposable
{
    private readonly Dictionary<uint, GlyphMetrics> _glyphs;
    private readonly IRenderer                      _renderer;
    private bool _disposed;

    public TextureHandle AtlasHandle { get; }
    public float         LineHeight  { get; }
    public float         Ascent      { get; }

    private Font(IRenderer renderer, TextureHandle atlas, GlyphMetrics[] glyphs, float lineHeight, float ascent)
    {
        _renderer   = renderer;
        AtlasHandle = atlas;
        LineHeight  = lineHeight;
        Ascent      = ascent;
        _glyphs     = new Dictionary<uint, GlyphMetrics>(glyphs.Length);
        foreach (var g in glyphs) _glyphs[g.Codepoint] = g;
    }

    /// <summary>
    /// Synchronously bakes <paramref name="path"/> at <paramref name="pixelSize"/>
    /// and uploads the atlas through the renderer. MUST be called from the
    /// render worker because the texture upload is pinned there.
    /// </summary>
    public static Font Load(IRenderer renderer, IFontLoader loader, string path, float pixelSize,
                            uint atlasSize = 512, uint firstCodepoint = 32, uint codepointCount = 95)
    {
        using var data = loader.LoadFontAsync(path, pixelSize, atlasSize, firstCodepoint, codepointCount)
                               .GetAwaiter().GetResult();
        var atlas = renderer.CreateTexture(data.AtlasWidth, data.AtlasHeight, data.AtlasRgba).Value;
        return new Font(renderer, atlas, data.Glyphs, data.LineHeight, data.Ascent);
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

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _renderer.DestroyTexture(AtlasHandle);
    }
}
