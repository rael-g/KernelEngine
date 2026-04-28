using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class RendererTests
{
    private static int _initializeCalled = 0;
    private static int _shutdownCalled = 0;
    private static int _destroyCalled = 0;
    private static int _clearColorCalled = 0;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockInitialize(ke_render* render)
    {
        _initializeCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockShutdown(ke_render* render)
    {
        _shutdownCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_render* render)
    {
        _destroyCalled++;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockClearColor(ke_render* render, float r, float g, float b, float a)
    {
        _clearColorCalled++;
        return ke_result.KE_OK;
    }

    [Fact]
    public void Lifecycle_CallsNativeFunctions()
    {
        _initializeCalled = 0;
        _shutdownCalled = 0;
        _destroyCalled = 0;

        ke_render* mock = (ke_render*)NativeMemory.Alloc((nuint)sizeof(ke_render));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_render));
        
        mock->on_initialize = &MockInitialize;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;

        {
            using var renderer = new Renderer(mock);
            renderer.Initialize();
            Assert.Equal(1, _initializeCalled);
        }

        Assert.Equal(1, _shutdownCalled);
        Assert.Equal(1, _destroyCalled);
        
        // Note: NativeMemory.Free(mock) is not needed if MockDestroy is expected to do it,
        // but here MockDestroy just increments a counter. In a real scenario it would free.
        // We'll free it here to be safe.
        NativeMemory.Free(mock);
    }

    private static int _frameCalled = 0;
    private static int _setOrthographicCalled = 0;
    private static int _setAmbientLightCalled = 0;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockFrame(ke_render* render)
    {
        _frameCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetOrthographic(ke_render* render, byte enabled)
    {
        _setOrthographicCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockSetAmbientLight(ke_render* render, float r, float g, float b)
    {
        _setAmbientLightCalled++;
        return ke_result.KE_OK;
    }

    [Fact]
    public void Methods_CallNativeFunctions()
    {
        _frameCalled = 0;
        _setOrthographicCalled = 0;
        _setAmbientLightCalled = 0;

        ke_render* mock = (ke_render*)NativeMemory.Alloc((nuint)sizeof(ke_render));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_render));
        
        mock->on_initialize = &MockInitialize;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;
        mock->frame = &MockFrame;
        mock->set_orthographic = &MockSetOrthographic;
        mock->set_ambient_light = &MockSetAmbientLight;
        mock->clear_color = &MockClearColor;

        using (var renderer = new Renderer(mock))
        {
            renderer.Frame();
            renderer.SetOrthographic(true);
            renderer.SetAmbientLight(1, 1, 1);
            renderer.ClearColor(1, 0, 0, 1);
            
            Assert.Equal(1, _frameCalled);
            Assert.Equal(1, _setOrthographicCalled);
            Assert.Equal(1, _setAmbientLightCalled);
            Assert.Equal(1, _clearColorCalled);
        }
        
        NativeMemory.Free(mock);
    }
}
