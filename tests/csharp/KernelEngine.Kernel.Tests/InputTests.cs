
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
}
