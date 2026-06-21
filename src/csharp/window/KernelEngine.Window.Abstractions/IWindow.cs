namespace KernelEngine.Window;

public interface IWindow : IDisposable
{
    bool ShouldClose();
    void PollEvents();
    (int Width, int Height) GetSize();
    nint GetNativeHandle();
}
