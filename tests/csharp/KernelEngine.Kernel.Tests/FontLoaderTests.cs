using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

using Xunit;

namespace EngineTests;

public class FontLoaderTests
{
    private static bool LastResult = true;
    private static bool DestroyCalled = false;
    private static bool FreeFontCalled = false;
    private static string? LastPath = null;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe global::KernelEngine.Result.Native.Result MockLoadFont(ke_font_loader* self, sbyte* path, float pixelSize, uint first, uint count, uint atlasSize, ke_font_data** out_font)
    {
        LastPath = Marshal.PtrToStringAnsi((IntPtr)path);

        *out_font = null;
        if (!LastResult) return global::KernelEngine.Result.Native.Result.General;

        var data = (ke_font_data*)NativeMemory.Alloc((nuint)sizeof(ke_font_data));
        data->atlas_width = 10;
        data->atlas_height = 10;
        data->atlas_rgba = (byte*)NativeMemory.Alloc(400);
        data->atlas_byte_count = 400;
        data->glyph_count = 1;
        data->glyphs = (KernelEngine.Text.GlyphMetrics*)NativeMemory.Alloc((nuint)sizeof(KernelEngine.Text.GlyphMetrics));
        data->glyphs[0].Codepoint = 65;
        data->line_height = 12;
        data->ascent = 10;

        *out_font = data;
        return global::KernelEngine.Result.Native.Result.Ok;
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockFreeFont(ke_font_loader* self, ke_font_data* data)
    {
        FreeFontCalled = true;
        if (data != null)
        {
            NativeMemory.Free(data->atlas_rgba);
            NativeMemory.Free(data->glyphs);
            NativeMemory.Free(data);
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockDestroy(ke_font_loader* self)
    {
        DestroyCalled = true;
    }

    private unsafe ke_font_loader_handle CreateMockHandle()
    {
        var ptr = (ke_font_loader*)NativeMemory.Alloc((nuint)sizeof(ke_font_loader));
        ptr->load_font = &MockLoadFont;
        ptr->free_font = &MockFreeFont;
        return new ke_font_loader_handle { @ref = ptr, destroy = &MockDestroy };
    }

    [Fact]
    public void Constructor_Throws_WhenNativeIsNull()
    {
        unsafe
        {
            Assert.Throws<ArgumentNullException>(() => new FontLoader(new ke_font_loader_handle()));
        }
    }

    [Fact]
    public void LoadFont_CallsNative()
    {
        ke_font_loader_handle h;
        unsafe { h = CreateMockHandle(); }

        FontLoader loader;
        unsafe { loader = new FontLoader(h); }

        LastPath = null;
        FreeFontCalled = false;
        LastResult = true;

        var baked = loader.LoadFont("test.ttf", 16, 32, 95, 512);
        var width = baked.Data.AtlasWidth;
        baked.Dispose();

        Assert.Equal("test.ttf", LastPath);
        Assert.Equal(10u, width);
        Assert.True(FreeFontCalled);

        unsafe { NativeMemory.Free(h.@ref); }
    }

    [Fact]
    public void LoadFont_Throws_WhenNativeFails()
    {
        ke_font_loader_handle h;
        unsafe { h = CreateMockHandle(); }

        FontLoader loader;
        unsafe { loader = new FontLoader(h); }

        LastResult = false;

        Assert.Throws<InvalidOperationException>(() => loader.LoadFont("test.ttf", 16, 32, 95, 512));

        LastResult = true;
        unsafe { NativeMemory.Free(h.@ref); }
    }

    [Fact]
    public void Dispose_CallsDestroy()
    {
        ke_font_loader_handle h;
        unsafe { h = CreateMockHandle(); }

        FontLoader loader;
        unsafe { loader = new FontLoader(h); }

        DestroyCalled = false;

        loader.Dispose();

        Assert.True(DestroyCalled);
    }
}
