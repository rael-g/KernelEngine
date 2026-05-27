using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

[Collection("KernelRegistry")]
public class InputTests
{
    [Fact]
    public void Input_CanBeCreated()
    {
        using var allocator = new MallocAllocator();
        using var input = new Input(allocator, null);
        Assert.NotNull(input);
    }

    [Fact]
    public void IsKeyDown_ReturnsFalse_ByDefault()
    {
        using var allocator = new MallocAllocator();
        using var input = new Input(allocator, null);
        Assert.False(input.IsKeyDown(65));
    }

    [Fact]
    public void CaptureSnapshot_ReturnsValidReader()
    {
        KernelThread.SetCurrentName("ke.main");
        using var allocator = new MallocAllocator();
        using var input = new Input(allocator, null);
        var reader = input.CaptureSnapshot();
        Assert.NotNull(reader);
        Assert.False(reader.IsKeyDown(65));
    }

    [Fact]
    public void Input_Current_ThrowsWhenNotSet()
    {
        Assert.Throws<InvalidOperationException>(() => InputContext.Current);
    }

    [Fact]
    public void InputReaderExtensions_WorkCorrectly()
    {
        KernelThread.SetCurrentName("ke.main");
        using var allocator = new MallocAllocator();
        using var input = new Input(allocator, null);
        
        var reader = input.CaptureSnapshot();
        Assert.False(reader.IsKeyDown(Key.W));
        Assert.False(reader.IsMouseButtonDown(MouseButton.Left));
    }
}
