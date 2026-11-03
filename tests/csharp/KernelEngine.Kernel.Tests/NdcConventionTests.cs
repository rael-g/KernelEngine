
using Xunit;

namespace EngineTests;

public class NdcConventionTests
{


    [Fact]
    public void Constructor_SetsZeroToOneDepth()
    {
        var conv = new NdcConvention { ZZeroToOne = false, YFlip = true };
        Assert.False(conv.ZZeroToOne);
    }

    [Fact]
    public void Constructor_SetsYFlip()
    {
        var conv = new NdcConvention { ZZeroToOne = false, YFlip = true };
        Assert.True(conv.YFlip);
    }
}
