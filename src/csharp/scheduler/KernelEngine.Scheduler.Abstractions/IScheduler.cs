namespace KernelEngine.Kernel;

/// <summary>Native scheduler used by the world for parallel system execution.</summary>
public interface IScheduler : IDisposable
{
    /// <summary>Dispatches an action onto a worker thread (load-balanced).</summary>
    void Dispatch(Action action);

    /// <summary>
    /// Dispatches an action onto a specific worker thread. Used to attach
    /// thread-affine work (e.g. native renderer calls) to a worker that has
    /// been named by an earlier task on the same thread.
    /// </summary>
    /// <param name="threadNum">Worker id, 1..NumWorkers.</param>
    void DispatchPinned(uint threadNum, Action action);

    /// <summary>Number of worker threads available for pinned dispatch (excluding the calling thread).</summary>
    uint NumWorkers { get; }
}
