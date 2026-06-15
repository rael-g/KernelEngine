using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Cross-thread queue for GPU resource commands. <c>ke.sim</c> enqueues create/destroy
/// requests via the implementation-provided <see cref="IResourceFactory"/>; <c>ke.render</c>
/// drains them by calling <see cref="Drain"/> once per frame (before reading the frame packet).
/// </summary>
public interface IResourceCommandQueue
{
    /// <summary>Returns a factory whose calls enqueue commands onto this queue.</summary>
    IResourceFactory CreateFactory();

    /// <summary>Drains all pending commands and executes them against <paramref name="renderer"/>.
    /// Must be called on <c>ke.render</c>.</summary>
    void Drain(IRenderer renderer);
}
