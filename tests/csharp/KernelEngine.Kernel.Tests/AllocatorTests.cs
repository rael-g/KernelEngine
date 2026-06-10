using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public unsafe class AllocatorTests
{
    [Fact]
    public void MallocAllocator_CanAllocate()
    {
        using var allocator = new MallocAllocator();
        var ptr = allocator.Allocate(1024);
        try
        {
            Assert.True((nint)ptr != 0);
        }
        finally
        {
            allocator.Free(ptr);
        }
    }

    [Fact]
    public void MallocAllocator_CanReallocate()
    {
        using var allocator = new MallocAllocator();
        var ptr = allocator.Allocate(1024);
        var newPtr = allocator.Reallocate(ptr, 2048);
        try
        {
            Assert.True((nint)newPtr != 0);
        }
        finally
        {
            allocator.Free(newPtr);
        }
    }

    [Fact]
    public void ArenaAllocator_Allocate_ReturnsNonNull()
    {
        using var allocator = new ArenaAllocator(1024);
        var ptr = allocator.Allocate(100);
        Assert.True((nint)ptr != 0);
    }

    [Fact]
    public void ArenaAllocator_MultipleAllocations_ReturnDifferentPointers()
    {
        using var allocator = new ArenaAllocator(1024);
        var ptr1 = allocator.Allocate(100);
        var ptr2 = allocator.Allocate(100);
        Assert.NotEqual((nint)ptr1, (nint)ptr2);
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
    public void ProxyAllocator_Allocate_IncrementsActiveAllocs()
    {
        using var inner = new MallocAllocator();
        using var proxy = new ProxyAllocator(inner, "TestProxy");
        var ptr = proxy.Allocate(1024);
        try
        {
            var stats = proxy.GetStats();
            Assert.Equal(1u, stats.ActiveAllocs);
        }
        finally
        {
            proxy.Free(ptr);
        }
    }

    [Fact]
    public void ProxyAllocator_Allocate_IncrementsActiveBytes()
    {
        using var inner = new MallocAllocator();
        using var proxy = new ProxyAllocator(inner, "TestProxy");
        var ptr = proxy.Allocate(1024);
        try
        {
            var stats = proxy.GetStats();
            Assert.Equal(1024u, stats.ActiveBytes);
        }
        finally
        {
            proxy.Free(ptr);
        }
    }

    [Fact]
    public void ProxyAllocator_Free_DecrementsActiveAllocs()
    {
        using var inner = new MallocAllocator();
        using var proxy = new ProxyAllocator(inner, "TestProxy");
        var ptr = proxy.Allocate(1024);
        proxy.Free(ptr);
        var stats = proxy.GetStats();
        Assert.Equal(0u, stats.ActiveAllocs);
    }

    [Fact]
    public void ProxyAllocator_Free_DecrementsActiveBytes()
    {
        using var inner = new MallocAllocator();
        using var proxy = new ProxyAllocator(inner, "TestProxy");
        var ptr = proxy.Allocate(1024);
        proxy.Free(ptr);
        var stats = proxy.GetStats();
        Assert.Equal(0u, stats.ActiveBytes);
    }
}
