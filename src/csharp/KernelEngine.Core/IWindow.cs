namespace KernelEngine.Core;

public interface IWindow : ISystem
{
    bool ShouldClose();
    void PollEvents();
}
