namespace KernelEngine.Kernel;

/// <summary>Native task scheduler used by the world for parallel system execution.</summary>
public interface ITaskScheduler : IDisposable
{
    /// <summary>Dispatches an action onto a worker thread.</summary>
    void Dispatch(Action action);
}
