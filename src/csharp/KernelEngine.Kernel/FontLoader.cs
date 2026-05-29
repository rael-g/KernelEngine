using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over a C kernel <c>ke_font_loader*</c>. Constructed by font plugins (e.g.
/// <c>AddTextStbTrueType()</c>) and registered as <see cref="IFontLoader"/> for game-code consumption.
/// Mirrors <see cref="ImageLoader"/>.
/// </summary>
public sealed unsafe class FontLoader : IFontLoader
{
    private ke_font_loader* _native;

    public FontLoader(ke_font_loader* native)
    {
        if (native == null) throw new ArgumentNullException(nameof(native));
        _native = native;
    }

    public Task<FontData> LoadFontAsync(
        string path,
        float pixelSize,
        uint atlasSize     = 512,
        uint firstCodepoint = 32,
        uint codepointCount = 95)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentNullException.ThrowIfNull(path);

        // Decode on a worker so ke.sim isn't blocked on disk + CPU bake.
        return Task.Run(() =>
        {
            var pathPtr = Marshal.StringToHGlobalAnsi(path);
            try
            {
                ke_font_data* data = null;
                var loader = _native;
                if (loader == null) throw new ObjectDisposedException(nameof(FontLoader));

                var res = loader->load_font(loader, (sbyte*)pathPtr, pixelSize,
                                            firstCodepoint, codepointCount, atlasSize, &data).ToManaged();
                KernelException.ThrowIfFailed(res);
                if (data == null) throw new InvalidOperationException("Font loader returned a null result.");

                try
                {
                    // Copy native atlas + glyphs into managed arrays so the native buffer can be freed.
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
                    loader->free_font(loader, data);
                }
            }
            finally { Marshal.FreeHGlobal(pathPtr); }
        });
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
