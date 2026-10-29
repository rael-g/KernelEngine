using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.TaskPool;

/// <summary>
/// The part of <see cref="TaskPool"/> that implements <see cref="ITaskPool"/> and exposes
/// native dispatch as <see cref="Task"/> and <see cref="KernelTask"/>.
/// </summary>
public unsafe partial class TaskPool : ITaskPool
{
    /// <inheritdoc/>
    void ITaskPool.Dispatch(Action action) => Dispatch(action);

    /// <inheritdoc/>
    public uint NumWorkers => GetNumWorkers();

    /// <summary>
    /// Schedules an <see cref="Action"/> on the native thread pool and returns a <see cref="KernelTask"/>.
    /// Identical ergonomics to <see cref="Task"/>: supports <c>await</c>, <c>IsCompleted</c>, and <c>Wait()</c>.
    /// </summary>
    public KernelTask DispatchKernelTask(Action action) => new(Dispatch(action));

    /// <summary>
    /// Schedules a <see cref="Func{TResult}"/> on the native thread pool and returns a <see cref="KernelTask{T}"/>.
    /// Identical ergonomics to <see cref="Task{T}"/>: supports <c>await</c>, <c>IsCompleted</c>, and <c>Result</c>.
    /// </summary>
    public KernelTask<T> DispatchKernelTask<T>(Func<T> func) => new(Dispatch(func));

    /// <summary>Schedules an <see cref="Action"/> on the native thread pool and returns an awaitable <see cref="Task"/>.</summary>
    public Task Dispatch(Action action)
    {
        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var job = new DispatchJob(action);
        var jobHandle = GCHandle.Alloc(job);
        var tcsHandle = GCHandle.Alloc((job, tcs));

        Handle->dispatch_on_complete(
            Handle,
            &NativeWorkCallback,
            (void*)GCHandle.ToIntPtr(jobHandle),
            &NativeCompletionCallback,
            (void*)GCHandle.ToIntPtr(tcsHandle)
        );

        return tcs.Task;
    }

    /// <summary>Schedules a <see cref="Func{TResult}"/> on the native thread pool and returns an awaitable <see cref="Task{TResult}"/>.</summary>
    public Task<T> Dispatch<T>(Func<T> func)
    {
        var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);

        Action wrapper = () =>
        {
            try { tcs.SetResult(func()); }
            catch (Exception ex) { tcs.SetException(ex); }
        };

        var actionHandle = GCHandle.Alloc(new DispatchJob(wrapper));
        var tcsHandle = GCHandle.Alloc(tcs);

        Handle->dispatch_on_complete(
            Handle,
            &NativeWorkCallback,
            (void*)GCHandle.ToIntPtr(actionHandle),
            &NativeGenericCompletionCallback,
            (void*)GCHandle.ToIntPtr(tcsHandle)
        );

        return tcs.Task;
    }

    /// <summary>
    /// A dispatched body and the exception it threw, if any, carried from the worker thread to the
    /// completion callback, which faults the task with it.
    /// </summary>
    private sealed class DispatchJob(Action body)
    {
        public readonly Action Body = body;
        public Exception? Failure;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeWorkCallback(void* data)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var job = (DispatchJob)handle.Target!;
        try
        {
            job.Body();
            return ke_result.KE_OK;
        }
        catch (Exception ex)
        {
            job.Failure = ex;
            return ke_result.KE_RESULT_GENERAL;
        }
        finally { handle.Free(); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCompletionCallback(ke_task* task, void* userData, ke_result result)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var (job, tcs) = ((DispatchJob, TaskCompletionSource))handle.Target!;
        handle.Free();
        if (job.Failure is { } ex) tcs.TrySetException(ex);
        else tcs.TrySetResult();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGenericCompletionCallback(ke_task* task, void* userData, ke_result result)
    {
        GCHandle.FromIntPtr((IntPtr)userData).Free();
    }
}
