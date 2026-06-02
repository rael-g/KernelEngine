using Xunit;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class InputCompositeTests
{
    [Fact]
    public void Vector2Composite_WASD_SetsCorrectKeys()
    {
        var binding = Vector2Composite.WASD();
        Assert.Equal(Key.W, binding.Up);
        Assert.Equal(Key.S, binding.Down);
        Assert.Equal(Key.A, binding.Left);
        Assert.Equal(Key.D, binding.Right);
    }

    [Fact]
    public void Vector2Composite_Arrows_SetsCorrectKeys()
    {
        var binding = Vector2Composite.Arrows();
        Assert.Equal(Key.Up, binding.Up);
        Assert.Equal(Key.Down, binding.Down);
        Assert.Equal(Key.Left, binding.Left);
        Assert.Equal(Key.Right, binding.Right);
    }

    [Fact]
    public void Vector1Composite_WS_SetsCorrectKeys()
    {
        var binding = Vector1Composite.WS();
        Assert.Equal(Key.S, binding.Negative);
        Assert.Equal(Key.W, binding.Positive);
    }

    [Fact]
    public void Vector1Composite_AD_SetsCorrectKeys()
    {
        var binding = Vector1Composite.AD();
        Assert.Equal(Key.A, binding.Negative);
        Assert.Equal(Key.D, binding.Positive);
    }

    [Fact]
    public void Vector1Composite_UpDown_SetsCorrectKeys()
    {
        var binding = Vector1Composite.UpDown();
        Assert.Equal(Key.Down, binding.Negative);
        Assert.Equal(Key.Up, binding.Positive);
    }

    [Fact]
    public void Vector1Composite_LeftRight_SetsCorrectKeys()
    {
        var binding = Vector1Composite.LeftRight();
        Assert.Equal(Key.Left, binding.Negative);
        Assert.Equal(Key.Right, binding.Positive);
    }
}
