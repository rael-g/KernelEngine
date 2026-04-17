using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class InputTests
{
    [Fact]
    public void Input_CanBeCreated()
    {
        using var allocator = new MallocAllocator();
        using var pipe = new MessagePipe(allocator, null);
        using var input = new Input(allocator, null, pipe);
        Assert.NotNull(input);
    }

    [Fact]
    public void IsKeyDown_ReturnsFalse_ByDefault()
    {
        using var allocator = new MallocAllocator();
        using var pipe = new MessagePipe(allocator, null);
        using var input = new Input(allocator, null, pipe);
        Assert.False(input.IsKeyDown(65));
    }

    [Fact]
    public void IsKeyPressed_ReturnsFalse_ByDefault()
    {
        using var allocator = new MallocAllocator();
        using var pipe = new MessagePipe(allocator, null);
        using var input = new Input(allocator, null, pipe);
        Assert.False(input.IsKeyPressed(65));
    }

    [Fact]
    public void IsKeyReleased_ReturnsFalse_ByDefault()
    {
        using var allocator = new MallocAllocator();
        using var pipe = new MessagePipe(allocator, null);
        using var input = new Input(allocator, null, pipe);
        Assert.False(input.IsKeyReleased(65));
    }
}
