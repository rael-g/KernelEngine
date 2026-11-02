namespace KernelEngine.Render;

/// <summary>
/// What a font needs from the active render backend: its atlas and its glyph table. Every method must be called from the thread that owns GPU resource creation.
/// </summary>
public interface IRenderResources
{
    /// <summary>
    /// Uploads an RGBA8 texture, <paramref name="rgba"/> being width by height by four bytes in row
    /// order. Throws when the
    /// upload fails.
    /// </summary>
    TextureHandle UploadTexture(string key, uint width, uint height, ReadOnlySpan<byte> rgba);

    /// <summary>
    /// Registers a font's glyph table with the UI pass, deduplicated by <paramref name="key"/>
    /// like <see cref="UploadTexture"/>. Throws when no font slot is free or the registration fails.
    /// </summary>
    FontHandle LoadFont(string key, TextureHandle atlas, ReadOnlySpan<FontGlyph> glyphs,
                        float lineHeight, float ascent);
}
