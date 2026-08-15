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
    private static void NativePinnedCallback(void* data)
    {
        var handle = GCHandle.FromIntPtr((IntPtr)data);
        var action = (Action)handle.Target!;
        try   { action(); }
        catch {  }
        finally { handle.Free(); }
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
        var tcs = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);

        var actionHandle = GCHandle.Alloc(action);
        var tcsHandle = GCHandle.Alloc(tcs);

        Handle->dispatch_on_complete(
            Handle,
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
        var tcs = new TaskCompletionSource<T>(TaskCreationOptions.RunContinuationsAsynchronously);

        Action wrapper = () =>
        {
            try { tcs.SetResult(func()); }
            catch (Exception ex) { tcs.SetException(ex); }
        };

        var actionHandle = GCHandle.Alloc(wrapper);
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
}
