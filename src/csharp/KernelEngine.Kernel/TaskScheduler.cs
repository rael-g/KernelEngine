using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper around <c>ke_task_scheduler</c>.
/// Dispatches work items to a native thread pool and bridges them to awaitable <see cref="Task"/>s.
/// </summary>
public sealed unsafe class TaskScheduler : IDisposable
{
    private ke_task_scheduler* _native;

    /// <summary>Gets the underlying native pointer.</summary>
    public ke_task_scheduler* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    public TaskScheduler(ke_task_scheduler* native) => _native = native;

    /// <summary>
    /// Schedules an <see cref="Action"/> on the native thread pool and returns a <see cref="KeTask"/>.
    /// Identical ergonomics to <see cref="Task"/>: supports <c>await</c>, <c>IsCompleted</c>, and <c>Wait()</c>.
    /// </summary>
    public KeTask DispatchKeTask(Action action) => new(Dispatch(action));

    /// <summary>
    /// Schedules a <see cref="Func{TResult}"/> on the native thread pool and returns a <see cref="KeTask{T}"/>.
    /// Identical ergonomics to <see cref="Task{T}"/>: supports <c>await</c>, <c>IsCompleted</c>, and <c>Result</c>.
    /// </summary>
    public KeTask<T> DispatchKeTask<T>(Func<T> func) => new(Dispatch(func));

    /// <summary>Schedules an <see cref="Action"/> on the native thread pool and returns an awaitable <see cref="Task"/>.</summary>
    public Task Dispatch(Action action)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);

        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        
        // Handle for the work action
        var actionHandle = GCHandle.Alloc(action);
        // Handle for the TCS to be used in completion
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
        
        // Wrap the function to set the result
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

        try
        {
            action();
        }
        catch (Exception)
        {
            // Exceptions in the work callback should be handled by the wrapper if it's a Task<T>
            // or logged if it's a fire-and-forget Action (though here it's always wrapped in a Task)
        }
        finally
        {
            handle.Free(); // Free the Action handle after work finishes
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCompletionCallback(ke_task* task, void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        var tcs = (TaskCompletionSource)handle.Target!;
        handle.Free(); // Free the TCS handle after completion

        tcs.TrySetResult();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeGenericCompletionCallback(ke_task* task, void* userData)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)userData);
        // The TCS is already updated by the wrapper Action, we just need to free the handle
        handle.Free();
    }

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
