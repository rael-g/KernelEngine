using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper around <c>ke_scheduler</c>.
/// Dispatches work items to a native thread pool and bridges them to awaitable <see cref="Task"/>s.
/// </summary>
public unsafe class Scheduler : IScheduler, INativeScheduler
{
    private ke_scheduler* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_scheduler*, void> _destroy;

    /// <inheritdoc/>
    void IScheduler.Dispatch(Action action) => Dispatch(action);  // fire-and-forget

    /// <inheritdoc/>
    void IScheduler.DispatchPinned(uint threadNum, Action action)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        ArgumentNullException.ThrowIfNull(action);

        var handle = GCHandle.Alloc(action);
        _native->dispatch_pinned(_native, threadNum, &NativePinnedCallback, (void*)GCHandle.ToIntPtr(handle));
        // Fire-and-forget; native callback frees the handle.
    }

    /// <inheritdoc/>
    public uint NumWorkers
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native->get_num_workers(_native);
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativePinnedCallback(void* data)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var action = (Action)handle.Target!;
        try   { action(); }
        catch { /* fire-and-forget; future versions can surface via on_complete */ }
        finally { handle.Free(); }
    }

    ke_scheduler* INativeScheduler.Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    public Scheduler(ke_scheduler_handle handle)
    {
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

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
        ObjectDisposedException.ThrowIf(_native == null, this);

        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var actionHandle = GCHandle.Alloc(action);
        var tcsHandle = GCHandle.Alloc(tcs);

        _native->dispatch_on_complete(
            _native,
            &NativeWorkCallback,
            (void*)GCHandle.ToIntPtr(actionHandle),
            &NativeCompletionCallback,
            (void*)GCHandle.ToIntPtr(tcsHandle)
        );

        return tcs.Task;
    }

    /// <summary>Schedules a <see cref="Func{TResult}"/> on the native thread pool and returns an awaitable <see cref="Task{TResult}"/>.</summary>
    public Task<T> Dispatch<T>(Func<T> func)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);

        Action wrapper = () =>
        {
            try { tcs.SetResult(func()); }
            catch (Exception ex) { tcs.SetException(ex); }
        };

        var actionHandle = GCHandle.Alloc(wrapper);
        var tcsHandle = GCHandle.Alloc(tcs);

        _native->dispatch_on_complete(
            _native,
            &NativeWorkCallback,
            (void*)GCHandle.ToIntPtr(actionHandle),
            &NativeGenericCompletionCallback,
            (void*)GCHandle.ToIntPtr(tcsHandle)
        );

        return tcs.Task;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeWorkCallback(void* data)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var action = (Action)handle.Target!;
        try { action(); }
        catch (Exception) { }
        finally { handle.Free(); }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCompletionCallback(ke_task* task, void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var tcs = (TaskCompletionSource)handle.Target!;
        handle.Free();
        tcs.TrySetResult();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGenericCompletionCallback(ke_task* task, void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        handle.Free();
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            if (_destroy != null) _destroy(_native);
            _native = null;
        }
    }
}
