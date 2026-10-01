using System.Runtime.InteropServices;
using KernelEngine.Text.Native;

namespace KernelEngine.Text;

/// <summary>
/// The parts of <see cref="FontLoader"/> that express the native surface in C# terms rather than
/// mirroring it: the async decode (native <c>load_font</c> is synchronous CPU work, so this wraps
/// it in <see cref="Task.Run(Action)"/> to keep the calling system off disk I/O and the CPU bake), and copying
/// the native atlas + glyph arrays into managed memory before <c>free_font</c> releases them.
/// Everything that is a direct image of the C ABI is generated in <c>Generated/FontLoader.g.cs</c>.
/// </summary>
public unsafe partial class FontLoader : IFontLoader
{
    /// <inheritdoc/>
    public Task<FontData> LoadFontAsync(
        string path,
        float pixelSize,
        uint atlasSize      = 512,
        uint firstCodepoint = 32,
        uint codepointCount = 95)
    {
        ArgumentNullException.ThrowIfNull(path);

        return Task.Run(() =>
        {
            var data = LoadFont(path, pixelSize, firstCodepoint, codepointCount, atlasSize);
            try
            {
                var atlasLen = (int)(data->atlas_width * data->atlas_height * 4);
                var atlas    = new byte[atlasLen];
                Marshal.Copy((IntPtr)data->atlas_rgba, atlas, 0, atlasLen);

                var glyphs = new GlyphMetrics[data->glyph_count];
                for (uint i = 0; i < data->glyph_count; i++)
                {
                    ref var g = ref data->glyphs[i];
                    glyphs[i] = new GlyphMetrics(
                        g.codepoint,
                        g.u0, g.v0, g.u1, g.v1,
                        g.bearing_x, g.bearing_y,
                        g.width, g.height,
                        g.advance_x);
                }

                return new FontData(atlas, data->atlas_width, data->atlas_height,
                                    glyphs, data->line_height, data->ascent);
            }
            finally
            {
                FreeFont(data);
            }
        });
    }
}
