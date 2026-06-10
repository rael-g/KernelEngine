using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class NdcConventionTests
{
    [Fact]
    public void Default_ZeroToOneDepth_IsTrue()
    {
        var conv = NdcConvention.Default;
        Assert.True(conv.ZeroToOneDepth);
    }

    [Fact]
    public void Default_YFlip_IsFalse()
    {
        var conv = NdcConvention.Default;
        Assert.False(conv.YFlip);
    }

    [Fact]
    public void Default_LeftHanded_IsFalse()
    {
        var conv = NdcConvention.Default;
        Assert.False(conv.LeftHanded);
    }

    [Fact]
    public void Constructor_SetsZeroToOneDepth()
    {
        var conv = new NdcConvention(false, true, true);
        Assert.False(conv.ZeroToOneDepth);
    }

    [Fact]
    public void Constructor_SetsYFlip()
    {
        var conv = new NdcConvention(false, true, true);
        Assert.True(conv.YFlip);
    }

    [Fact]
    public void Constructor_SetsLeftHanded()
    {
        var conv = new NdcConvention(false, true, true);
        Assert.True(conv.LeftHanded);
    }
}
