namespace KernelEngine.Kernel;

/// <summary>
/// A named OS thread owned by the engine. Lifecycle: create → run action → dispose joins.
/// </summary>
public interface IKernelThread : IDisposable
{
    /// <summary>Name assigned at creation. Visible in debuggers/profilers when a
    /// <c>IDevPlatform</c> is registered.</summary>
    string Name { get; }
}
