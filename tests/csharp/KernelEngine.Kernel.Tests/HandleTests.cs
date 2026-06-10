using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class HandleTests
{
    [Fact]
    public void MeshHandle_None_IsInvalid()
    {
        Assert.False(MeshHandle.None.IsValid);
    }

    [Fact]
    public void MeshHandle_None_HasMaxValue()
    {
        Assert.Equal(uint.MaxValue, MeshHandle.None.Value);
    }

    [Fact]
    public void TextureHandle_White_IsValid()
    {
        Assert.True(TextureHandle.White.IsValid);
    }

    [Fact]
    public void TextureHandle_White_HasZeroValue()
    {
        Assert.Equal(0u, TextureHandle.White.Value);
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
