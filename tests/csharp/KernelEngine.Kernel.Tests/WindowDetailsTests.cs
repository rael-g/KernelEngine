using System.Runtime.InteropServices;
using Xunit;

namespace EngineTests;

public unsafe class WindowDetailsTests
{
    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static bool MockInit(ke_window* self, ke_error** out_error) => true;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static bool MockGetSize(ke_window* self, int* w, int* h, ke_error** out_error)
    {
        *w = 1920;
        *h = 1080;
        return true;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void* MockGetHandle(ke_window* self) => (void*)0xDEADBEEF;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_window* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static bool MockShutdown(ke_window* self, ke_error** out_error) => true;

    private static ke_window_handle MakeHandle(ke_window* ptr) =>
        new ke_window_handle { @ref = ptr, destroy = &MockDestroy };

    [Fact]
    public void GetSize_ReturnsCorrectValues()
    {
        var mock = (ke_window*)NativeMemory.AllocZeroed((nuint)sizeof(ke_window));
        mock->on_initialize = &MockInit;
        mock->get_size = &MockGetSize;
        mock->on_shutdown = &MockShutdown;

        using (var window = new Window(MakeHandle(mock)))
        {
            var (width, height) = window.GetSize();
            Assert.Equal(1920, width);
            Assert.Equal(1080, height);
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

        using (var window = new Window(MakeHandle(mock)))
        {
            unchecked
            {
                Assert.Equal((nint)0xDEADBEEF, window.GetNativeHandle());
            }
        }
        NativeMemory.Free(mock);
    }
}
