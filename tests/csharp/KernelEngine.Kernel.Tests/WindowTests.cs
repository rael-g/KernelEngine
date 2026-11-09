using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

using Xunit;

namespace EngineTests;

[Collection("KernelRegistry")]
public unsafe class WindowTests
{
    private static int _destroyCalled = 0;
    private static int _shouldCloseCalled = 0;

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static void MockDestroy(ke_window* window)
    {
        _destroyCalled++;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static bool MockShouldClose(ke_window* window)
    {
        _shouldCloseCalled++;
        return true;
    }

    private static ke_window_handle MakeHandle(ke_window* ptr) =>
        new ke_window_handle { @ref = ptr, destroy = &MockDestroy };

    [Fact]
    public void Dispose_DestroysTheNativeWindow()
    {
        _destroyCalled = 0;

        ke_window* mock = (ke_window*)NativeMemory.Alloc((nuint)sizeof(ke_window));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_window));

        {
            using var window = new Window(MakeHandle(mock));
        }

        Assert.Equal(1, _destroyCalled);

        NativeMemory.Free(mock);
    }

    [Fact]
    public void ShouldClose_CallsNativeFunction()
    {
        _shouldCloseCalled = 0;

        ke_window* mock = (ke_window*)NativeMemory.Alloc((nuint)sizeof(ke_window));
        NativeMemory.Clear(mock, (nuint)sizeof(ke_window));
        mock->should_close = &MockShouldClose;

        using (var window = new Window(MakeHandle(mock)))
        {
            Assert.True(window.ShouldClose());
            Assert.Equal(1, _shouldCloseCalled);
        }

        NativeMemory.Free(mock);
    }
}
