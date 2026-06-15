using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class Physics2DContextTests
{
    [Fact]
    public void Set_UpdatesValues()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);

        Physics2DContext.Set(physics, system);

        Assert.Same(physics, Physics2DContext.PhysicsOrNull);
        Assert.Same(system, Physics2DContext.SystemOrNull);
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void Physics_Throws_WhenNull()
    {
        Physics2DContext.Set(null, null);
        Assert.Throws<InvalidOperationException>(() => Physics2DContext.Physics);
    }

    [Fact]
    public void System_Throws_WhenNull()
    {
        Physics2DContext.Set(null, null);
        Assert.Throws<InvalidOperationException>(() => Physics2DContext.System);
    }
}
