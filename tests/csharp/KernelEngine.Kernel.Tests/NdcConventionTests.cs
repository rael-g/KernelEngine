
using Xunit;

namespace EngineTests;

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
    public void Constructor_SetsZeroToOneDepth()
    {
        var conv = new NdcConvention(false, true);
        Assert.False(conv.ZeroToOneDepth);
    }

    [Fact]
    public void Constructor_SetsYFlip()
    {
        var conv = new NdcConvention(false, true);
        Assert.True(conv.YFlip);
    }
}
