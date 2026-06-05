using System.Runtime.InteropServices;
using Xunit;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel.Tests;

public class RenderPassContextTests
{
    private static string? LastTextureName = null;
    private static uint MockWidth = 800;
    private static uint MockHeight = 600;

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe ke_texture_handle MockGetTexture(ke_render_pass_ctx* self, sbyte* name)
    {
        LastTextureName = Marshal.PtrToStringAnsi((IntPtr)name);
        if (LastTextureName == "existent") return new ke_texture_handle { idx = 42 };
        return new ke_texture_handle { idx = uint.MaxValue };
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static unsafe void MockGetBackbufferSize(ke_render_pass_ctx* self, uint* w, uint* h)
    {
        *w = MockWidth;
        *h = MockHeight;
    }

    private unsafe ke_render_pass_ctx* CreateMockNative()
    {
        var ptr = (ke_render_pass_ctx*)NativeMemory.Alloc((nuint)sizeof(ke_render_pass_ctx));
        ptr->get_texture = &MockGetTexture;
        ptr->get_backbuffer_size = &MockGetBackbufferSize;
        return ptr;
    }

    [Fact]
    public unsafe void GetTexture_CallsNative()
    {
        var native = CreateMockNative();
        var ctx = new RenderPassContext(native);
        LastTextureName = null;
        
        var handle = ctx.GetTexture("existent");
        
        Assert.Equal("existent", LastTextureName);
        Assert.Equal(42u, handle.Value);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void GetTexture_ReturnsNone_WhenNativeReturnsMaxValue()
    {
        var native = CreateMockNative();
        var ctx = new RenderPassContext(native);
        
        var handle = ctx.GetTexture("missing");
        
        Assert.Equal(TextureHandle.None, handle);
        NativeMemory.Free(native);
    }

    [Fact]
    public unsafe void GetBackbufferSize_CallsNative()
    {
        var native = CreateMockNative();
        var ctx = new RenderPassContext(native);
        MockWidth = 1024;
        MockHeight = 768;
        
        var (w, h) = ctx.GetBackbufferSize();
        
        Assert.Equal(1024u, w);
        Assert.Equal(768u, h);
        NativeMemory.Free(native);
    }
}
