using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class AbstractionsTests
{
    [Fact]
    public void FrameworkBackends_Required_ThrowsWhenNull()
    {
        var old = FrameworkBackends.Default;
        FrameworkBackends.Default = null;
        try {
            Assert.Throws<InvalidOperationException>(() => FrameworkBackends.Required);
        } finally {
            FrameworkBackends.Default = old;
        }
    }

    [Fact]
    public void FrameworkBackends_Required_ReturnsInstanceWhenSet()
    {
        var old = FrameworkBackends.Default;
        var mock = Substitute.For<IFrameworkBackendFactory>();
        FrameworkBackends.Default = mock;
        try {
            Assert.Same(mock, FrameworkBackends.Required);
        } finally {
            FrameworkBackends.Default = old;
        }
    }

    [Fact]
    public void FrameworkBackends_ScenePropertiesResolver_IsNotNull()
    {
        Assert.NotNull(FrameworkBackends.ScenePropertiesResolver);
    }

    [Fact]
    public void FrameworkBackends_ScenePropertiesResolver_ResolvesNotNullProperties()
    {
        var world = Substitute.For<IWorld>();
        var props = FrameworkBackends.ScenePropertiesResolver(world, 1);
        Assert.NotNull(props);
    }
}
