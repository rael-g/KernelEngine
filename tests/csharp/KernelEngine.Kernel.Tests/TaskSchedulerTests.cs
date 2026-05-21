using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

/// <summary>
/// Tests for <see cref="TaskScheduler"/>, <see cref="KernelTask"/>, and <see cref="KernelTask{T}"/>.
///
/// The native scheduler is mocked via a synthetic <c>ke_task_scheduler</c> struct
/// whose function pointers execute work synchronously on the calling thread.
/// No real enki threads are started — we test only the C# wrapper logic.
/// </summary>
public sealed class TaskSchedulerTests
{
    // ── Sync mock callbacks ───────────────────────────────────────────────────
    //
    // [UnmanagedCallersOnly] methods cannot be called from managed code directly,
    // so SyncDispatch cannot delegate to SyncDispatchOnComplete — logic is inlined.

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe ke_task* SyncDispatchOnComplete(
        ke_task_scheduler* self,
        delegate* unmanaged[Cdecl]<void*, void> func,
        void* data,
        delegate* unmanaged[Cdecl]<ke_task*, void*, void> on_complete,
        void* user_data)
    {
        if (func != null) func(data);
        if (on_complete != null) on_complete(null, user_data);
        return null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe ke_task* SyncDispatch(
        ke_task_scheduler* self,
        delegate* unmanaged[Cdecl]<void*, void> func,
        void* data)
    {
        if (func != null) func(data);
        return null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe bool AlwaysCompleted(ke_task_scheduler* self, ke_task* task) => true;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NoopDestroy(ke_task_scheduler* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NoopWait(ke_task_scheduler* self, ke_task* task) { }

    // ── Mock handle ───────────────────────────────────────────────────────────

    private sealed class MockSchedulerHandle : IDisposable
    {
        private unsafe ke_task_scheduler* _ptr;
        public TaskScheduler Scheduler { get; }

        public unsafe MockSchedulerHandle()
        {
            _ptr = (ke_task_scheduler*)NativeMemory.Alloc((nuint)sizeof(ke_task_scheduler));
            *_ptr = new ke_task_scheduler
            {
                dispatch_on_complete = &SyncDispatchOnComplete,
                dispatch             = &SyncDispatch,
                is_completed         = &AlwaysCompleted,
                wait                 = &NoopWait,
                destroy              = &NoopDestroy,
            };
            Scheduler = new TaskScheduler(_ptr);
        }

        public unsafe void Dispose()
        {
            Scheduler.Dispose();
            NativeMemory.Free(_ptr);
            _ptr = null;
        }
    }

    // ── Task (existing Dispatch API) ──────────────────────────────────────────

    [Fact]
    public async Task Dispatch_Action_Executes()
    {
        using var mock = new MockSchedulerHandle();
        bool ran = false;
        await mock.Scheduler.Dispatch(() => { ran = true; });
        Assert.True(ran);
    }

    [Fact]
    public async Task Dispatch_Func_ReturnsResult()
    {
        using var mock = new MockSchedulerHandle();
        int result = await mock.Scheduler.Dispatch(() => 42);
        Assert.Equal(42, result);
    }

    [Fact]
    public async Task Dispatch_Func_PropagatesException()
    {
        using var mock = new MockSchedulerHandle();
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => mock.Scheduler.Dispatch<int>(() => throw new InvalidOperationException("boom")));
    }

    // ── KernelTask (new DispatchKernelTask API) ───────────────────────────────────────

    [Fact]
    public async Task DispatchKernelTask_Action_IsAwaitable()
    {
        using var mock = new MockSchedulerHandle();
        bool ran = false;
        KernelTask task = mock.Scheduler.DispatchKernelTask(() => { ran = true; });
        await task;
        Assert.True(ran);
    }

    [Fact]
    public async Task DispatchKernelTask_Action_IsCompletedAfterAwait()
    {
        using var mock = new MockSchedulerHandle();
        KernelTask task = mock.Scheduler.DispatchKernelTask(() => { });
        await task;
        Assert.True(task.IsCompleted);
    }

    [Fact]
    public void DispatchKernelTask_Action_WaitBlocks()
    {
        using var mock = new MockSchedulerHandle();
        bool ran = false;
        KernelTask task = mock.Scheduler.DispatchKernelTask(() => { ran = true; });
        task.Wait();
        Assert.True(ran);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_ReturnsResult()
    {
        using var mock = new MockSchedulerHandle();
        KernelTask<int> task = mock.Scheduler.DispatchKernelTask(() => 99);
        int result = await task;
        Assert.Equal(99, result);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_IsCompletedAfterAwait()
    {
        using var mock = new MockSchedulerHandle();
        KernelTask<string> task = mock.Scheduler.DispatchKernelTask(() => "hello");
        await task;
        Assert.True(task.IsCompleted);
    }

    [Fact]
    public void DispatchKernelTask_Func_ResultBlocks()
    {
        using var mock = new MockSchedulerHandle();
        KernelTask<float> task = mock.Scheduler.DispatchKernelTask(() => 3.14f);
        Assert.Equal(3.14f, task.Result);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_PropagatesException()
    {
        using var mock = new MockSchedulerHandle();
        KernelTask<int> task = mock.Scheduler.DispatchKernelTask<int>(
            () => throw new ArgumentException("fail"));
        await Assert.ThrowsAsync<ArgumentException>(async () => await task);
    }

    [Fact]
    public async Task DispatchKernelTask_ComposesLikeTask()
    {
        // KernelTask<T> composes with async/await identically to Task<T>
        using var mock = new MockSchedulerHandle();
        var s = mock.Scheduler;

        static async Task<int> ComputeAsync(TaskScheduler s)
        {
            int a = await s.DispatchKernelTask(() => 10);
            int b = await s.DispatchKernelTask(() => 32);
            return a + b;
        }

        Assert.Equal(42, await ComputeAsync(s));
    }

    [Fact]
    public async Task DispatchKernelTask_CompatibleWithWhenAll()
    {
        using var mock = new MockSchedulerHandle();
        var tasks = Enumerable.Range(1, 5)
            .Select(i => mock.Scheduler.DispatchKernelTask(() => i * i))
            .ToList();

        int[] results = await Task.WhenAll(tasks.Select(async t => await t));
        Assert.Equal([1, 4, 9, 16, 25], results);
    }
}
