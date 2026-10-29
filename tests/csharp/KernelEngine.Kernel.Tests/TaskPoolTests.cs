using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

using Xunit;

using PoolImpl = KernelEngine.TaskPool.TaskPool;

namespace EngineTests;

/// <summary>
/// Tests for <see cref="PoolImpl"/>, <see cref="KernelTask"/>, and <see cref="KernelTask{T}"/>.
///
/// The native task pool is mocked via a synthetic <c>ke_task_pool</c> struct
/// whose function pointers execute work synchronously on the calling thread.
/// No real enki threads are started — we test only the C# wrapper logic.
/// </summary>
public sealed class TaskPoolTests
{

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe ke_task* SyncDispatchOnComplete(
        ke_task_pool* self,
        delegate* unmanaged[Cdecl]<void*, ke_result> func,
        void* data,
        delegate* unmanaged[Cdecl]<ke_task*, void*, ke_result, void> on_complete,
        void* user_data)
    {
        var result = func != null ? func(data) : ke_result.KE_OK;
        if (on_complete != null) on_complete(null, user_data, result);
        return null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe ke_task* SyncDispatch(
        ke_task_pool* self,
        delegate* unmanaged[Cdecl]<void*, ke_result> func,
        void* data)
    {
        if (func != null) func(data);
        return null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe bool AlwaysCompleted(ke_task_pool* self, ke_task* task) => true;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe void NoopDestroy(ke_task_pool* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static unsafe ke_result NoopWait(ke_task_pool* self, ke_task* task) => ke_result.KE_OK;

    private sealed class MockTaskPoolHandle : IDisposable
    {
        private unsafe ke_task_pool* _ptr;
        public PoolImpl Pool { get; }

        public unsafe MockTaskPoolHandle()
        {
            _ptr = (ke_task_pool*)NativeMemory.Alloc((nuint)sizeof(ke_task_pool));
            *_ptr = new ke_task_pool
            {
                dispatch_on_complete = &SyncDispatchOnComplete,
                dispatch = &SyncDispatch,
                is_completed = &AlwaysCompleted,
                wait = &NoopWait,
            };
            Pool = new PoolImpl(new ke_task_pool_handle { @ref = _ptr, destroy = &NoopDestroy });
        }

        public unsafe void Dispose()
        {
            Pool.Dispose();
            NativeMemory.Free(_ptr);
            _ptr = null;
        }
    }

    [Fact]
    public async Task Dispatch_Action_Executes()
    {
        using var mock = new MockTaskPoolHandle();
        bool ran = false;
        await mock.Pool.Dispatch(() => { ran = true; });
        Assert.True(ran);
    }

    [Fact]
    public async Task Dispatch_Action_PropagatesException()
    {
        using var mock = new MockTaskPoolHandle();
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => mock.Pool.Dispatch(() => throw new InvalidOperationException("boom")));
    }

    [MethodImpl(MethodImplOptions.NoInlining)]
    private static async Task<WeakReference> DispatchAndForget(PoolImpl pool)
    {
        var body = new object();
        await pool.Dispatch(() => GC.KeepAlive(body));
        return new WeakReference(body);
    }

    [Fact]
    public async Task Dispatch_Action_ReleasesTheHandleRootingTheBody()
    {
        using var mock = new MockTaskPoolHandle();
        WeakReference body = await DispatchAndForget(mock.Pool);

        GC.Collect();
        GC.WaitForPendingFinalizers();
        GC.Collect();

        Assert.False(body.IsAlive);
    }

    [Fact]
    public async Task Dispatch_Func_ReturnsResult()
    {
        using var mock = new MockTaskPoolHandle();
        int result = await mock.Pool.Dispatch(() => 42);
        Assert.Equal(42, result);
    }

    [Fact]
    public async Task Dispatch_Func_PropagatesException()
    {
        using var mock = new MockTaskPoolHandle();
        await Assert.ThrowsAsync<InvalidOperationException>(
            () => mock.Pool.Dispatch<int>(() => throw new InvalidOperationException("boom")));
    }

    [Fact]
    public async Task DispatchKernelTask_Action_IsAwaitable()
    {
        using var mock = new MockTaskPoolHandle();
        bool ran = false;
        KernelTask task = mock.Pool.DispatchKernelTask(() => { ran = true; });
        await task;
        Assert.True(ran);
    }

    [Fact]
    public async Task DispatchKernelTask_Action_IsCompletedAfterAwait()
    {
        using var mock = new MockTaskPoolHandle();
        KernelTask task = mock.Pool.DispatchKernelTask(() => { });
        await task;
        Assert.True(task.IsCompleted);
    }

    [Fact]
    public void DispatchKernelTask_Action_WaitBlocks()
    {
        using var mock = new MockTaskPoolHandle();
        bool ran = false;
        KernelTask task = mock.Pool.DispatchKernelTask(() => { ran = true; });
        task.Wait();
        Assert.True(ran);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_ReturnsResult()
    {
        using var mock = new MockTaskPoolHandle();
        KernelTask<int> task = mock.Pool.DispatchKernelTask(() => 99);
        int result = await task;
        Assert.Equal(99, result);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_IsCompletedAfterAwait()
    {
        using var mock = new MockTaskPoolHandle();
        KernelTask<string> task = mock.Pool.DispatchKernelTask(() => "hello");
        await task;
        Assert.True(task.IsCompleted);
    }

    [Fact]
    public void DispatchKernelTask_Func_ResultBlocks()
    {
        using var mock = new MockTaskPoolHandle();
        KernelTask<float> task = mock.Pool.DispatchKernelTask(() => 3.14f);
        Assert.Equal(3.14f, task.Result);
    }

    [Fact]
    public async Task DispatchKernelTask_Func_PropagatesException()
    {
        using var mock = new MockTaskPoolHandle();
        KernelTask<int> task = mock.Pool.DispatchKernelTask<int>(
            () => throw new ArgumentException("fail"));
        await Assert.ThrowsAsync<ArgumentException>(async () => await task);
    }

    [Fact]
    public async Task DispatchKernelTask_ComposesLikeTask()
    {
        using var mock = new MockTaskPoolHandle();
        var s = mock.Pool;

        static async Task<int> ComputeAsync(PoolImpl s)
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
        using var mock = new MockTaskPoolHandle();
        var tasks = Enumerable.Range(1, 5)
            .Select(i => mock.Pool.DispatchKernelTask(() => i * i))
            .ToList();

        int[] results = await Task.WhenAll(tasks.Select(async t => await t));
        Assert.Equal([1, 4, 9, 16, 25], results);
    }
}
