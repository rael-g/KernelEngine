namespace KernelEngine.Kernel;

public interface IWindow : IDisposable
{
    bool ShouldClose();
    Result PollEvents();
    Result<(int Width, int Height)> GetSize();
    nint GetNativeHandle();
}
