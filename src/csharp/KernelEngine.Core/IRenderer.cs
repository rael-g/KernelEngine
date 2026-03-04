namespace KernelEngine.Core;

public interface IRenderer : ISystem
{
    void ClearColor(float r, float g, float b, float a);
}
