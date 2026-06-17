using System.Runtime.InteropServices;
using Xunit;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel.Tests;

public class FontLoaderTests
{
    private static ke_result LastResult = ke_result.KE_OK;
    private static bool DestroyCalled = false;
    private static bool FreeFontCalled = false;
    private static string? LastPath = null;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_result MockLoadFont(ke_font_loader* self, sbyte* path, float pixelSize, uint first, uint count, uint atlasSize, ke_font_data** outData, ke_error** out_error)
    {
        LastPath = Marshal.PtrToStringAnsi((IntPtr)path);

        if (LastResult != ke_result.KE_OK) return LastResult;

        var data = (ke_font_data*)NativeMemory.Alloc((nuint)sizeof(ke_font_data));
        data->atlas_width = 10;
        data->atlas_height = 10;
        data->atlas_rgba = (byte*)NativeMemory.Alloc(400); // 10*10*4
        data->glyph_count = 1;
        data->glyphs = (ke_glyph_metrics*)NativeMemory.Alloc((nuint)sizeof(ke_glyph_metrics));
        data->glyphs[0].codepoint = 65;
        data->line_height = 12;
        data->ascent = 10;

        *outData = data;
        return ke_result.KE_OK;
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

    private unsafe ke_font_loader* CreateMockNative()
    {
        var ptr = (ke_font_loader*)NativeMemory.Alloc((nuint)sizeof(ke_font_loader));
        ptr->load_font = &MockLoadFont;
        ptr->free_font = &MockFreeFont;
        ptr->destroy = &MockDestroy;
        return ptr;
    }

    [Fact]
    public void Constructor_Throws_WhenNativeIsNull()
    {
        unsafe 
        { 
            Assert.Throws<ArgumentNullException>(() => new FontLoader(null)); 
        }
    }

    [Fact]
    public async Task LoadFontAsync_CallsNative()
    {
        IntPtr native;
        unsafe { native = (IntPtr)CreateMockNative(); }
        
        FontLoader loader;
        unsafe { loader = new FontLoader((ke_font_loader*)native); }
        
        LastPath = null;
        FreeFontCalled = false;
        LastResult = ke_result.KE_OK;

        var data = await loader.LoadFontAsync("test.ttf", 16);

        Assert.Equal("test.ttf", LastPath);
        Assert.Equal(10u, data.AtlasWidth);
        Assert.True(FreeFontCalled);
        
        unsafe { NativeMemory.Free((void*)native); }
    }

    [Fact]
    public async Task LoadFontAsync_Throws_WhenNativeFails()
    {
        IntPtr native;
        unsafe { native = (IntPtr)CreateMockNative(); }
        
        FontLoader loader;
        unsafe { loader = new FontLoader((ke_font_loader*)native); }
        
        LastResult = ke_result.KE_ERROR;

        await Assert.ThrowsAsync<KernelException>(() => loader.LoadFontAsync("test.ttf", 16));

        LastResult = ke_result.KE_OK;
        unsafe { NativeMemory.Free((void*)native); }
    }

    [Fact]
    public void Dispose_CallsDestroy()
    {
        IntPtr native;
        unsafe { native = (IntPtr)CreateMockNative(); }
        
        FontLoader loader;
        unsafe { loader = new FontLoader((ke_font_loader*)native); }
        
        DestroyCalled = false;

        loader.Dispose();

        Assert.True(DestroyCalled);
        unsafe { NativeMemory.Free((void*)native); }
    }
}
