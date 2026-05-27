using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class AllocatorTests
{
    [Fact]
    public void MallocAllocator_CanAllocateAndFree()
    {
        using var allocator = new MallocAllocator();
        var ptr = allocator.Allocate(1024);
        Assert.True((nint)ptr != 0);
        allocator.Free(ptr);
    }

    [Fact]
    public void MallocAllocator_CanReallocate()
    {
        using var allocator = new MallocAllocator();
        var ptr = allocator.Allocate(1024);
        var newPtr = allocator.Reallocate(ptr, 2048);
        Assert.True((nint)newPtr != 0);
        allocator.Free(newPtr);
    }

    [Fact]
    public void ArenaAllocator_CanAllocate()
    {
        using var allocator = new ArenaAllocator(1024);
        var ptr = allocator.Allocate(100);
        Assert.True((nint)ptr != 0);
        
        var ptr2 = allocator.Allocate(100);
        Assert.NotEqual((nint)ptr, (nint)ptr2);
    }

    [Fact]
    public void ArenaAllocator_Reset_AllowsReuse()
    {
        using var allocator = new ArenaAllocator(1024);
        var ptr1 = allocator.Allocate(512);
        allocator.Reset();
        var ptr2 = allocator.Allocate(512);
        Assert.Equal((nint)ptr1, (nint)ptr2);
    }

    [Fact]
    public void ProxyAllocator_TracksStats()
    {
        using var inner = new MallocAllocator();
        using var proxy = new ProxyAllocator(inner, "TestProxy");
        
        var ptr = proxy.Allocate(1024);
        var stats = proxy.GetStats();
        Assert.Equal(1u, stats.ActiveAllocs);
        Assert.Equal(1024u, stats.ActiveBytes);

        proxy.Free(ptr);
        stats = proxy.GetStats();
        Assert.Equal(0u, stats.ActiveAllocs);
        Assert.Equal(0u, stats.ActiveBytes);
    }
}
