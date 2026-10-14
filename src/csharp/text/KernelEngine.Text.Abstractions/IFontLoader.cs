namespace KernelEngine.Text;

/// <summary>
/// Bakes a font file into a glyph atlas and metrics on a worker thread, so the caller does not
/// block on disk I/O or the CPU bake.
/// </summary>
public interface IFontLoader : IDisposable
{
    /// <summary>
    /// Bakes a glyph atlas for the codepoint range
    /// <c>[firstCodepoint, firstCodepoint + codepointCount)</c> at <paramref name="pixelSize"/>.
    /// Runs on a worker thread (CPU-only).
    /// </summary>
    /// <param name="path">TTF/OTF file path.</param>
    /// <param name="pixelSize">Em-square size in pixels (e.g. 32).</param>
    /// <param name="atlasSize">Square atlas dimension; ASCII fits in 256, larger ranges need
    /// bigger.</param>
    /// <param name="firstCodepoint">First codepoint to bake (inclusive). 32 = space.</param>
    /// <param name="codepointCount">How many consecutive codepoints to bake. 95 covers printable
    /// ASCII (32..126).</param>
    Task<FontData> LoadFontAsync(
        string path,
        float pixelSize,
        uint atlasSize     = 512,
        uint firstCodepoint = 32,
        uint codepointCount = 95);
}
