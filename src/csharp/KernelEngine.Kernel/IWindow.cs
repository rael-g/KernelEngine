using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

public interface IWindow : IDisposable
{
    unsafe ke_window* Native { get; }
    bool ShouldClose();
    Result PollEvents();
    Result<(int Width, int Height)> GetSize();
    nint GetNativeHandle();
}
