using KernelEngine.Framework.Animation;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class EasingTests
{
    [Fact]
    public void Linear_ReturnsVerbatim()
    {
        Assert.Equal(0.0f, Easing.Linear(0.0f));
        Assert.Equal(0.5f, Easing.Linear(0.5f));
        Assert.Equal(1.0f, Easing.Linear(1.0f));
    }

    [Fact]
    public void EaseIn_ReturnsSquared()
    {
        Assert.Equal(0.0f, Easing.EaseIn(0.0f));
        Assert.Equal(0.25f, Easing.EaseIn(0.5f));
        Assert.Equal(1.0f, Easing.EaseIn(1.0f));
    }

    [Fact]
    public void EaseOut_ReturnsInverseSquared()
    {
        Assert.Equal(0.0f, Easing.EaseOut(0.0f));
        Assert.Equal(0.75f, Easing.EaseOut(0.5f));
        Assert.Equal(1.0f, Easing.EaseOut(1.0f));
    }

    [Fact]
    public void EaseInOut_ReturnsExpected()
    {
        Assert.Equal(0.0f, Easing.EaseInOut(0.0f));
        Assert.Equal(0.5f, Easing.EaseInOut(0.5f));
        Assert.Equal(1.0f, Easing.EaseInOut(1.0f));
    }
}
