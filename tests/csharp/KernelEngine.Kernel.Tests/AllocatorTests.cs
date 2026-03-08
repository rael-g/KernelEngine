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
}
