using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class MessagePipeTests
{
    [Fact]
    public void MessagePipe_CanBroadcastAndReceive()
    {
        using var allocator = new MallocAllocator();
        using var logger = new Logger(allocator);
        using var pipe = new MessagePipe(allocator, logger);
        
        int data = 12345;
        pipe.Broadcast(100, data);
        
        bool ok = pipe.TryReceive<int>(100, out int received);
        Assert.True(ok);
        Assert.Equal(12345, received);
    }

    [Fact]
    public void MessagePipe_FilterWorks()
    {
        using var allocator = new MallocAllocator();
        using var pipe = new MessagePipe(allocator, null);
        
        pipe.Broadcast(1, 10);
        pipe.Broadcast(2, 20);
        
        bool ok1 = pipe.TryReceive<int>(1, out int v1);
        Assert.True(ok1);
        Assert.Equal(10, v1);
        
        bool ok2 = pipe.TryReceive<int>(2, out int v2);
        Assert.True(ok2);
        Assert.Equal(20, v2);
    }
}
