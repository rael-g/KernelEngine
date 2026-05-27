using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class SemaphoreTests
{
    [Fact]
    public void Semaphore_CanSignalAndWait()
    {
        using var allocator = new MallocAllocator();
        using var semaphore = KernelSemaphore.Create(allocator, 0);

        // This is tricky to test in a single thread if it blocks.
        // But we can signal first, then wait should not block.
        semaphore.Signal();
        semaphore.Wait();
        
        // If we reach here, it worked.
    }

    [Fact]
    public void Semaphore_MultipleSignals_AllowsMultipleWait()
    {
        using var allocator = new MallocAllocator();
        using var semaphore = KernelSemaphore.Create(allocator, 0);

        semaphore.Signal();
        semaphore.Signal();
        
        semaphore.Wait();
        semaphore.Wait();
    }
}
