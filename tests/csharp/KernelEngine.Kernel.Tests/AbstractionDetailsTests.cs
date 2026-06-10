using KernelEngine.Kernel;
using Xunit;
using System.Numerics;

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
    public void Result_StaticMethods_Work()
    {
        Assert.True(Result.Ok().IsOk);
        Assert.True(Result.Error(KernelResult.NotFound).IsError);
        Assert.Equal(KernelResult.NotFound, Result.Error(KernelResult.NotFound).Code);
    }

    [Fact]
    public void Result_ToString_ReturnsExpected()
    {
        Assert.Equal("Ok", Result.Ok().ToString());
        Assert.Equal("Error(NotFound)", Result.Error(KernelResult.NotFound).ToString());
    }

    [Fact]
    public void GenericResult_ImplicitConversion_Works()
    {
        Result<int> r = 123;
        Assert.True(r.IsOk);
        Assert.Equal(123, r.Value);

        Result<int> err = KernelResult.Io;
        Assert.True(err.IsError);
        Assert.Equal(KernelResult.Io, err.Code);

        Result nonGeneric = err;
        Assert.Equal(KernelResult.Io, nonGeneric.Code);
    }

    [Fact]
    public void GenericResult_ToString_ReturnsExpected()
    {
        Result<int> r = 123;
        Assert.Equal("Ok(123)", r.ToString());
        Result<string> err = KernelResult.NotFound;
        Assert.Equal("Error(NotFound)", err.ToString());
    }

    [Fact]
    public void Handles_None_AreInvalid()
    {
        Assert.False(MeshHandle.None.IsValid);
        Assert.False(TextureHandle.None.IsValid);
        Assert.False(MaterialHandle.None.IsValid);
        Assert.False(ShadowMapHandle.None.IsValid);
    }

    [Fact]
    public void Handles_NewValue_AreValid()
    {
        Assert.True(new MeshHandle(0).IsValid);
        Assert.True(new TextureHandle(1).IsValid);
        Assert.True(new MaterialHandle(2).IsValid);
        Assert.True(new ShadowMapHandle(3).IsValid);
    }

    [Fact]
    public void TextureHandle_White_IsValid()
    {
        Assert.True(TextureHandle.White.IsValid);
        Assert.Equal(0u, TextureHandle.White.Value);
    }

    [Fact]
    public void Vertex_Initialization_Works()
    {
        var v = new Vertex { X = 1, Y = 2, Z = 3, Nx = 0, Ny = 1, Nz = 0, U = 0.5f, V = 0.5f };
        Assert.Equal(1f, v.X);
        Assert.Equal(1f, v.Ny);
        Assert.Equal(0.5f, v.U);
    }

    [Fact]
    public void Transform_Identity_IsCorrect()
    {
        var t = Transform.Identity;
        Assert.Equal(Vector3.Zero, t.Position);
        Assert.Equal(Quaternion.Identity, t.Rotation);
        Assert.Equal(Vector3.One, t.Scale);
    }

    [Fact]
    public void Result_Generic_AccessValue_ThrowsOnError()
    {
        Result<string> r = KernelResult.Io;
        var ex = Assert.Throws<KernelException>(() => r.Value);
        Assert.Equal(KernelResult.Io, ex.Result);
    }

    [Fact]
    public void Result_Error_ReturnsExpected()
    {
        var r = Result.Error(KernelResult.NotFound);
        Assert.True(r.IsError);
        Assert.Equal(KernelResult.NotFound, r.Code);
    }

    [Fact]
    public void Result_Equals_Works()
    {
        Result r1 = KernelResult.Ok;
        Result r2 = KernelResult.Ok;
        Result r3 = KernelResult.Error;
        
        Assert.True(r1.Equals(r2));
        Assert.False(r1.Equals(r3));
        Assert.True(r1 == r2);
        Assert.True(r1 != r3);
    }

    [Fact]
    public void GenericResult_Equals_Works()
    {
        Result<int> r1 = 123;
        Result<int> r2 = 123;
        Result<int> r3 = KernelResult.Error;
        
        Assert.True(r1.Equals(r2));
        Assert.False(r1.Equals(r3));
    }
}
