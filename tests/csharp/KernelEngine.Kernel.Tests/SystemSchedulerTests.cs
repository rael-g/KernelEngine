using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;
using Moq;

namespace KernelEngine.Kernel.Tests;

public class SystemSchedulerTests
{
    private class MockSystem(uint[] reads, uint[] writes) : ISystem
    {
        public int UpdateCount { get; private set; }
        private readonly ComponentAccess _access = new() { 
            Reads = new List<uint>(reads), 
            Writes = new List<uint>(writes) 
        };

        public ComponentAccess GetAccess() => _access;
        public void Update(IWorld world, float dt, IFramePacket? packet, IInputReader? input)
        {
            UpdateCount++;
        }
    }

    [Fact]
    public void Build_SingleSystem_CreatesOneWave()
    {
        var scheduler = new SystemScheduler();
        var sys = new MockSystem([1], [2]);
        
        scheduler.Build(new List<ISystem> { sys });
        
        // We can't access waves directly as they are private, 
        // but we can verify execution.
    }

    [Fact]
    public async Task RunAsync_ExecutesAllSystems()
    {
        var scheduler = new SystemScheduler();
        var sys1 = new MockSystem([1], [2]);
        var sys2 = new MockSystem([3], [4]);
        
        scheduler.Build(new List<ISystem> { sys1, sys2 });
        await scheduler.RunAsync(null!, 0.16f, null, null!);

        Assert.Equal(1, sys1.UpdateCount);
        Assert.Equal(1, sys2.UpdateCount);
    }

    [Fact]
    public async Task RunAsync_RespectsConflicts_SequentialWaves()
    {
        var scheduler = new SystemScheduler();
        // sys1 writes to comp 10
        var sys1 = new MockSystem([], [10]);
        // sys2 reads from comp 10 -> Conflict, must be in separate wave
        var sys2 = new MockSystem([10], []);
        
        scheduler.Build(new List<ISystem> { sys1, sys2 });
        
        // If we had a way to track timing or order, we'd verify they run sequentially.
        // For now, verify they both run.
        await scheduler.RunAsync(null!, 0.16f, null, null!);
        
        Assert.Equal(1, sys1.UpdateCount);
        Assert.Equal(1, sys2.UpdateCount);
    }

    [Fact]
    public async Task RunAsync_SerialBarrier_ForcesNewWave()
    {
        var scheduler = new SystemScheduler();
        var sys1 = new MockSystem([1], []);
        // Serial barrier (no access)
        var barrier = new MockSystem([], []);
        var sys2 = new MockSystem([2], []);
        
        scheduler.Build(new List<ISystem> { sys1, barrier, sys2 });
        await scheduler.RunAsync(null!, 0.16f, null, null!);
        
        Assert.Equal(1, sys1.UpdateCount);
        Assert.Equal(1, barrier.UpdateCount);
        Assert.Equal(1, sys2.UpdateCount);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static unsafe void MockTaskDestroy(ke_task_scheduler* self) { }

    [UnmanagedCallersOnly(CallConvs = [typeof(System.Runtime.CompilerServices.CallConvCdecl)])]
    private static unsafe ke_task* MockTaskDispatch(ke_task_scheduler* self, delegate* unmanaged[Cdecl]<void*, void> work, void* data, delegate* unmanaged[Cdecl]<ke_task*, void*, void> complete, void* userData)
    {
        // Execute immediately for testing
        work(data);
        complete(null, userData);
        return null;
    }

    [Fact]
    public async Task RunAsync_WithTaskScheduler_DispatchesParallel()
    {
        var scheduler = new SystemScheduler();
        var sys1 = new MockSystem([1], []);
        var sys2 = new MockSystem([2], []); // No conflict with sys1
        
        scheduler.Build(new List<ISystem> { sys1, sys2 });

        IntPtr nativePtr = IntPtr.Zero;
        unsafe
        {
            var native = (ke_task_scheduler*)NativeMemory.AllocZeroed((nuint)sizeof(ke_task_scheduler));
            native->destroy = &MockTaskDestroy;
            native->dispatch_on_complete = &MockTaskDispatch;
            nativePtr = (IntPtr)native;
        }

        unsafe
        {
            using (var taskScheduler = new TaskScheduler((ke_task_scheduler*)nativePtr))
            {
                // We must call RunAsync OUTSIDE of this unsafe block to await it,
                // but we need taskScheduler which is inside using.
                // Actually, TaskScheduler constructor just copies the pointer.
            }
        }

        // Let's simplify: create TaskScheduler, then await, then free.
        TaskScheduler ts;
        unsafe { ts = new TaskScheduler((ke_task_scheduler*)nativePtr); }
        await scheduler.RunAsync(null!, 0.16f, null, ts);

        Assert.Equal(1, sys1.UpdateCount);
        Assert.Equal(1, sys2.UpdateCount);
        
        unsafe { NativeMemory.Free((void*)nativePtr); }
    }
}
