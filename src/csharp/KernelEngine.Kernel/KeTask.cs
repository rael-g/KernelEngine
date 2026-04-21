using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// A handle to a native task being executed by the <see cref="TaskScheduler"/>.
/// Can be awaited in C#.
/// </summary>
public unsafe struct KeTask
{
    private readonly ke_task* _native;
    private readonly ke_task_scheduler* _scheduler;

    internal KeTask(ke_task* native, ke_task_scheduler* scheduler)
    {
        _native = native;
        _scheduler = scheduler;
    }

    public KeTaskAwaiter GetAwaiter() => new KeTaskAwaiter(_native, _scheduler);
}

public unsafe struct KeTaskAwaiter : ICriticalNotifyCompletion
{
    private readonly ke_task* _task;
    private readonly ke_task_scheduler* _scheduler;

    public KeTaskAwaiter(ke_task* task, ke_task_scheduler* scheduler)
    {
        _task = task;
        _scheduler = scheduler;
    }

    public bool IsCompleted => _scheduler->is_completed(_scheduler, _task);

    public void GetResult()
    {
        if (_task != null)
        {
            _scheduler->wait(_scheduler, _task);
        }
    }

    public void OnCompleted(Action continuation) => UnsafeOnCompleted(continuation);

    public void UnsafeOnCompleted(Action continuation)
    {
        // For KeTask to be fully awaitable via callbacks, it must have been dispatched 
        // with a completion callback. Currently, TaskScheduler handles this via TaskCompletionSource.
        // This struct exists to represent a raw native task handle.
    }
}
