namespace KernelEngine.Kernel;

/// <summary>
/// A named OS thread owned by the engine. Lifecycle: create → run action → dispose joins.
/// </summary>
public interface IKernelThread : IDisposable
{
    /// <summary>Name assigned at creation. Visible in debuggers/profilers when a
    /// <c>IDevPlatform</c> is registered.</summary>
    string Name { get; }

    /// <summary>Blocks the calling thread until this one finishes.</summary>
    void Join();

    /// <summary>Blocks until the thread finishes or the timeout expires. Returns true if finished.</summary>
    bool Join(int timeoutMs);
}
