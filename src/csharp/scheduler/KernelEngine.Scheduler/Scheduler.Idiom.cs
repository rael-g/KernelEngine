using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Scheduler;

/// <summary>
/// The parts of <see cref="Scheduler"/> that express fire-and-forget native
/// dispatch as C# async — Task/TaskCompletionSource bridging, GCHandle-rooted
/// trampolines for the three [raw_callback] slots kabic does not generate a
/// method for (there is no ABI-derivable answer to "what should this look
/// like in C#" the way there is for a fallible slot or a sequence; the value
/// surface here is inherently this language's own async idiom). Everything
/// that is a direct image of the C ABI is generated in
/// <c>Generated/Scheduler.g.cs</c>.
/// </summary>
public unsafe partial class Scheduler : IScheduler
{
    /// <inheritdoc/>
    void IScheduler.Dispatch(Action action) => Dispatch(action);

    /// <inheritdoc/>
    void IScheduler.DispatchPinned(uint threadNum, Action action)
    {
        ArgumentNullException.ThrowIfNull(action);

        var handle = GCHandle.Alloc(action);
        Handle->dispatch_pinned(Handle, threadNum, &NativePinnedCallback, (void*)GCHandle.ToIntPtr(handle));
    }

    /// <inheritdoc/>
    public uint NumWorkers => GetNumWorkers();

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativePinnedCallback(void* data, ke_error_type** outFailure)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var action = (Action)handle.Target!;
        try { action(); }
        catch (Exception ex) { UnobservedDispatchFailure?.Invoke(ex); }
        finally { handle.Free(); }
    }

    /// <summary>
    /// Raised when work dispatched through <see cref="IScheduler.DispatchPinned"/> throws.
    /// That overload answers nothing, so there is no task to fault and no caller to throw
    /// at; without a subscriber the failure is only observable here.
    /// </summary>
    public static event Action<Exception>? UnobservedDispatchFailure;

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
    /// Carries a dispatched body and whatever it threw from the worker thread to the
    /// completion callback. The native channel hands on a <c>ke_error_type</c>, which
    /// survives the thread crossing but names only the category; the exception itself
    /// never leaves managed memory, so it reaches the task intact.
    /// </summary>
    private sealed class DispatchJob(Action body)
    {
        public readonly Action Body = body;
        public Exception? Failure;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeWorkCallback(void* data, ke_error_type** outFailure)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var job = (DispatchJob)handle.Target!;
        try { job.Body(); }
        catch (Exception ex) { job.Failure = ex; }
        finally { handle.Free(); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCompletionCallback(ke_task* task, void* userData, ke_error_type* failure)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var (job, tcs) = ((DispatchJob, TaskCompletionSource))handle.Target!;
        handle.Free();
        if (job.Failure is { } ex) tcs.TrySetException(ex);
        else tcs.TrySetResult();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGenericCompletionCallback(ke_task* task, void* userData, ke_error_type* failure)
    {
        GCHandle.FromIntPtr((IntPtr)userData).Free();
    }
}
