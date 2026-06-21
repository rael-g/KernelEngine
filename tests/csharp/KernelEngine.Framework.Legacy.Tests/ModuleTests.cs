
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class ScenePropertiesTests
{
    [Fact]
    public void EmptySceneProperties_IsEmpty_IsTrue()
    {
        var props = EmptySceneProperties.Instance;
        Assert.True(props.IsEmpty);
    }

    [Fact]
    public void EmptySceneProperties_GetString_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal("fallback", props.GetString("key", "fallback"));
    }

    [Fact]
    public void EmptySceneProperties_GetFloat_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal(42f, props.GetFloat("key", 42f));
    }

    [Fact]
    public void EmptySceneProperties_GetInt_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal(123L, props.GetInt("key", 123L));
    }

    [Fact]
    public void EmptySceneProperties_GetBool_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.True(props.GetBool("key", true));
    }

    [Fact]
    public void EmptySceneProperties_GetVector2_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal(System.Numerics.Vector2.One, props.GetVector2("key", System.Numerics.Vector2.One));
    }

    [Fact]
    public void EmptySceneProperties_GetVector3_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal(System.Numerics.Vector3.UnitX, props.GetVector3("key", System.Numerics.Vector3.UnitX));
    }

    [Fact]
    public void EmptySceneProperties_GetVector4_ReturnsFallback()
    {
        var props = EmptySceneProperties.Instance;
        Assert.Equal(System.Numerics.Vector4.UnitW, props.GetVector4("key", System.Numerics.Vector4.UnitW));
    }

    [Fact]
    public void EmptySceneProperties_TryGetString_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetString("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetFloat_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetFloat("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetInt_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetInt("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetBool_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetBool("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetVector2_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetVector2("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetVector3_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetVector3("key", out _));
    }

    [Fact]
    public void EmptySceneProperties_TryGetVector4_ReturnsFalse()
    {
        var props = EmptySceneProperties.Instance;
        Assert.False(props.TryGetVector4("key", out _));
    }
}
