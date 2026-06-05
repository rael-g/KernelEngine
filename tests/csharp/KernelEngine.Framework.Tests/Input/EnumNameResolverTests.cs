using Xunit;
using KernelEngine.Framework;

namespace KernelEngine.Framework.Tests;

public class EnumNameResolverTests
{
    public enum TestEnum { Alpha, Beta, Gamma }

    [Fact]
    public void Parse_ReturnsCorrectValue()
    {
        var v = EnumNameResolver<TestEnum>.Parse("Alpha");
        Assert.Equal(TestEnum.Alpha, v);
    }

    [Fact]
    public void Parse_Throws_OnUnknownName()
    {
        Assert.Throws<ArgumentException>(() => EnumNameResolver<TestEnum>.Parse("Unknown"));
    }

    [Fact]
    public void All_ReturnsAllValues()
    {
        var all = EnumNameResolver<TestEnum>.All().ToList();
        Assert.Equal(3, all.Count);
        Assert.Contains(all, x => x.Name == "Alpha" && x.Value == TestEnum.Alpha);
        Assert.Contains(all, x => x.Name == "Beta" && x.Value == TestEnum.Beta);
        Assert.Contains(all, x => x.Name == "Gamma" && x.Value == TestEnum.Gamma);
    }
}
