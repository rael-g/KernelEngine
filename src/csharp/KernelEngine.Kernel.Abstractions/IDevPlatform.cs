namespace KernelEngine.Kernel;

/// <summary>
/// Dev-only platform facilities (thread naming for debuggers/profilers, crash handlers, etc.).
/// Optional service — Framework checks for presence and degrades gracefully when absent.
/// </summary>
public interface IDevPlatform : IDisposable
{
    /// <summary>
    /// Publishes the calling thread's name to the OS, making it visible in debuggers and profilers.
    /// </summary>
    void SetOsThreadName(string name);
}
