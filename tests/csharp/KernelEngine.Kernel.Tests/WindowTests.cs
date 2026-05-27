using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
public unsafe class WindowTests
{
    private static int _initializeCalled = 0;
    private static int _shutdownCalled = 0;
    private static int _destroyCalled = 0;
    private static int _shouldCloseCalled = 0;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockInitialize(ke_window* window)
    {
        _initializeCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static ke_result MockShutdown(ke_window* window)
    {
        _shutdownCalled++;
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_window* window)
    {
        _destroyCalled++;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static byte MockShouldClose(ke_window* window)
    {
        _shouldCloseCalled++;
        return 1;
    }

    [Fact]
    public void Lifecycle_CallsNativeFunctions()
    {
        _initializeCalled = 0;
        _shutdownCalled = 0;
        _destroyCalled = 0;

        ke_window* mock = (ke_window*)NativeMemory.Alloc((nuint)sizeof(ke_window));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_window));
        
        mock->on_initialize = &MockInitialize;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;

        {
            using var window = new Window(mock);
            Assert.Equal(1, _initializeCalled);
        }

        Assert.Equal(1, _shutdownCalled);
        Assert.Equal(1, _destroyCalled);
        
        NativeMemory.Free(mock);
    }

    [Fact]
    public void ShouldClose_CallsNativeFunction()
    {
        _shouldCloseCalled = 0;

        ke_window* mock = (ke_window*)NativeMemory.Alloc((nuint)sizeof(ke_window));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_window));
        
        mock->on_initialize = &MockInitialize;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;
        mock->should_close = &MockShouldClose;

        using (var window = new Window(mock))
        {
            Assert.True(window.ShouldClose());
            Assert.Equal(1, _shouldCloseCalled);
        }
        
        NativeMemory.Free(mock);
    }
}
