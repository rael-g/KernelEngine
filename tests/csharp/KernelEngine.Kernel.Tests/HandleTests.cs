
using Xunit;

namespace EngineTests;

public class HandleTests
{
    [Fact]
    public void MeshHandle_None_IsInvalid()
    {
        Assert.False(MeshHandle.None.IsValid);
    }

    [Fact]
    public void MeshHandle_None_IsAllBitsZero()
    {
        // The property the whole scheme rests on: memory that arrives zeroed —
        // a component the scene file created, a struct left default — already
        // reads as no handle, with nobody having to seed it.
        Assert.Equal(0u, MeshHandle.None.Value);
    }

    [Fact]
    public void DefaultConstructedHandleIsNotValid()
    {
        Assert.False(default(MeshHandle).IsValid);
        Assert.False(default(TextureHandle).IsValid);
        Assert.False(default(MaterialHandle).IsValid);
        Assert.False(default(ShadowMapHandle).IsValid);
        Assert.False(default(FontHandle).IsValid);
    }

    [Fact]
    public void TextureHandle_None_IsInvalid()
    {
        Assert.False(TextureHandle.None.IsValid);
    }

    [Fact]
    public void MaterialHandle_Custom_IsValid()
    {
        var handle = new MaterialHandle(123);
        Assert.True(handle.IsValid);
    }

    [Fact]
    public void MaterialHandle_Custom_HasCorrectValue()
    {
        var handle = new MaterialHandle(123);
        Assert.Equal(123u, handle.Value);
    }

    [Fact]
    public void ShadowMapHandle_None_IsInvalid()
    {
        Assert.False(ShadowMapHandle.None.IsValid);
    }
}
