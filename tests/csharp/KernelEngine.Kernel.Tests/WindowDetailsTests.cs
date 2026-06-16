using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class WindowDetailsTests
{
    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static int MockInit(ke_window* self) => (int)ke_result.KE_OK;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static int MockGetSize(ke_window* self, int* w, int* h)
    {
        *w = 1920;
        *h = 1080;
        return (int)ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void* MockGetHandle(ke_window* self) => (void*)0xDEADBEEF;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_window* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static int MockShutdown(ke_window* self) => (int)ke_result.KE_OK;

    [Fact]
    public void GetSize_ReturnsCorrectValues()
    {
        var mock = (ke_window*)NativeMemory.AllocZeroed((nuint)sizeof(ke_window));
        mock->on_initialize = &MockInit;
        mock->get_size = &MockGetSize;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;

        using (var window = new Window(mock))
        {
            var res = window.GetSize();
            Assert.True(res.IsOk);
            Assert.Equal(1920, res.Value.Width);
            Assert.Equal(1080, res.Value.Height);
        }
        NativeMemory.Free(mock);
    }

    [Fact]
    public void GetNativeHandle_ReturnsPointer()
    {
        var mock = (ke_window*)NativeMemory.AllocZeroed((nuint)sizeof(ke_window));
        mock->on_initialize = &MockInit;
        mock->get_native_handle = &MockGetHandle;
        mock->on_shutdown = &MockShutdown;
        mock->destroy = &MockDestroy;

        using (var window = new Window(mock))
        {
            unchecked
            {
                Assert.Equal((nint)0xDEADBEEF, window.GetNativeHandle());
            }
        }
        NativeMemory.Free(mock);
    }
}
