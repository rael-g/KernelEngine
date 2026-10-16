using Kabic.Bindings;

namespace Kabic.Tests;

public sealed class UsingBlockTests
{
    [Fact]
    public void SystemComesFirstAndEachFirstSegmentIsItsOwnGroup()
    {
        var text = "using KernelEngine.Common.Native;\nusing System.Runtime.InteropServices;\n\nnamespace A;\n";

        var normalized = UsingBlock.Normalize(text);

        Assert.Equal("using System.Runtime.InteropServices;\n\nusing KernelEngine.Common.Native;\n\nnamespace A;\n", normalized);
    }

    [Fact]
    public void AnAliasOrStaticDirectiveLeavesTheFileAsItWas()
    {
        var text = "using static System.Math;\nusing B;\n\nnamespace A;\n";

        Assert.Equal(text, UsingBlock.Normalize(text));
    }

    [Fact]
    public void AFileAlreadyInOrderIsUnchanged()
    {
        var text = "using System;\nusing System.IO;\n\nnamespace A;\n";

        Assert.Equal(text, UsingBlock.Normalize(text));
    }
}
