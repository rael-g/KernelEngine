namespace KernelEngine.TaskPool;

/// <summary>
/// Native task pool used by the world for parallel system execution. Extends
/// <see cref="INativeTaskPool"/> so whoever needs the pointer can ask for it
/// rather than casting back to whichever concrete type this happens to be.
/// </summary>
public interface ITaskPool : IDisposable, INativeTaskPool
{
    /// <summary>Dispatches an action onto a worker thread (load-balanced).</summary>
    void Dispatch(Action action);

    /// <summary>Number of worker threads in the pool, excluding the calling thread.</summary>
    uint NumWorkers { get; }
}
