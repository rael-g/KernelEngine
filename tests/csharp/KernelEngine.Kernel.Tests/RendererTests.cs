using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class RendererTests
{
    private static int _initializeCalled = 0;
    private static int _frameCalled = 0;
    private static int _clearColorCalled = 0;
    private static float _lastR, _lastG, _lastB, _lastA;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockOnInitialize(ke_render* self) { _initializeCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockFrame(ke_render* self) { _frameCalled++; return ke_result.KE_OK; }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockClearColor(ke_render* self, float r, float g, float b, float a) 
    { 
        _clearColorCalled++; 
        _lastR = r; _lastG = g; _lastB = b; _lastA = a;
        return ke_result.KE_OK; 
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_render* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockOnShutdown(ke_render* self) { return ke_result.KE_OK; }

    // Helper to create a mock vtable
    private ke_render* CreateMock()
    {
        var mock = (ke_render*)NativeMemory.AllocZeroed((nuint)sizeof(ke_render));
        mock->on_initialize = &MockOnInitialize;
        mock->frame = &MockFrame;
        mock->clear_color = &MockClearColor;
        mock->destroy = &MockDestroy;
        mock->on_shutdown = &MockOnShutdown;
        return mock;
    }

    [Fact]
    public void Initialize_IncrementsCounter()
    {
        _initializeCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.Initialize();
            Assert.Equal(1, _initializeCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void Frame_IncrementsCounter()
    {
        _frameCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.Frame();
            Assert.Equal(1, _frameCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_IncrementsCounter()
    {
        _clearColorCalled = 0;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(1, 0, 0, 1);
            Assert.Equal(1, _clearColorCalled);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_PassesCorrectRed()
    {
        _lastR = -1;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(0.5f, 0, 0, 1);
            Assert.Equal(0.5f, _lastR);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ClearColor_Vector4_PassesCorrectGreen()
    {
        _lastG = -1;
        var mock = CreateMock();
        using (var renderer = new Renderer(mock))
        {
            renderer.ClearColor(new Vector4(0, 0.7f, 0, 1));
            Assert.Equal(0.7f, _lastG);
        }
        NativeMemory.Free(mock);
    }
}
