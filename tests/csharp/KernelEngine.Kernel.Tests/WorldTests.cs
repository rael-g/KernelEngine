using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class WorldTests
{
    [Fact]
    public void World_Constants()
    {
        Assert.Equal(0UL, (ulong)NativeMethods.KE_ENTITY_INVALID);
    }
}
