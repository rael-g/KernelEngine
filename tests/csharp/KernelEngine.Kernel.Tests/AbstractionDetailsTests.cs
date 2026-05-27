using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class AbstractionDetailsTests
{
    [Fact]
    public void ComponentAccess_InitializesLists()
    {
        var access = new ComponentAccess
        {
            Reads = [1, 2],
            Writes = [3]
        };

        Assert.Contains(1u, access.Reads);
        Assert.Contains(3u, access.Writes);
    }

    [Fact]
    public void ComponentAccess_None_IsEmpty()
    {
        var none = ComponentAccess.None;
        Assert.Empty(none.Reads);
        Assert.Empty(none.Writes);
    }

    [Fact]
    public void EcsQuery_Deconstructs()
    {
        ulong[] entities = [42];
        int[] data = [123];
        var query = new EcsQuery<int>(entities, data);

        var (e, d) = query;
        Assert.Equal(42u, e[0]);
        Assert.Equal(123, d[0]);
    }
}
