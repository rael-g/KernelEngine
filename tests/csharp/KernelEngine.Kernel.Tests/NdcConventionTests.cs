using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class NdcConventionTests
{
    [Fact]
    public void Default_ReturnsVulkanConvention()
    {
        var conv = NdcConvention.Default;
        Assert.True(conv.ZeroToOneDepth);
        Assert.False(conv.YFlip);
        Assert.False(conv.LeftHanded);
    }

    [Fact]
    public void Constructor_SetsProperties()
    {
        var conv = new NdcConvention(false, true, true);
        Assert.False(conv.ZeroToOneDepth);
        Assert.True(conv.YFlip);
        Assert.True(conv.LeftHanded);
    }
}
