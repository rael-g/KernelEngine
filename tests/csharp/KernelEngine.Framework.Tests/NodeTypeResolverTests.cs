using KernelEngine.Framework;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class NodeTypeResolverTests
{
    [Fact]
    public void Resolve_EmptyName_ReturnsNull()
    {
        Assert.Null(NodeTypeResolver.Resolve(""));
        Assert.Null(NodeTypeResolver.Resolve(null!));
    }

    [Fact]
    public void Resolve_ShortName_WorksForBuiltInTypes()
    {
        var t = NodeTypeResolver.Resolve("Camera");
        Assert.Equal(typeof(Camera), t);
    }

    [Fact]
    public void Resolve_FullyQualifiedName_Works()
    {
        var t = NodeTypeResolver.Resolve("KernelEngine.Framework.Sprite2D");
        Assert.Equal(typeof(Sprite2D), t);
    }

    [Fact]
    public void Resolve_UnknownType_ReturnsNull()
    {
        Assert.Null(NodeTypeResolver.Resolve("NonExistentNode"));
    }
}
