
using Xunit;

namespace EngineTests;

[Collection("KernelRegistry")]
public class InputTests
{
    [Fact]
    public void Input_CanBeCreated()
    {
        using var input = new DefaultInput();
        Assert.NotNull(input);
    }

    [Fact]
    public void IsKeyDown_ReturnsFalse_ByDefault()
    {
        using var input = new DefaultInput();
        Assert.False(input.IsKeyDown(Key.A));
    }

    [Fact]
    public void CaptureSnapshot_ReturnsValidReader()
    {
        using var input = new DefaultInput();
        var reader = input.CaptureSnapshot();
        Assert.NotNull(reader);
        Assert.False(reader.IsKeyDown(Key.A));
    }

    [Fact]
    public void InputReaderExtensions_WorkCorrectly()
    {
        using var input = new DefaultInput();

        var reader = input.CaptureSnapshot();
        Assert.False(reader.IsKeyDown(Key.W));
        Assert.False(reader.IsMouseButtonDown(MouseButton.Left));
    }
}
