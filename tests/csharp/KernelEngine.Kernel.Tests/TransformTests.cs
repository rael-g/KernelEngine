using System.Numerics;

using Xunit;

namespace EngineTests;

[Collection("KernelRegistry")]
public class TransformTests
{
    [Fact]
    public void Identity_Position_IsZero()
    {
        Assert.Equal(Vector3.Zero, Transform.Identity.Position);
    }

    [Fact]
    public void Identity_Rotation_IsIdentity()
    {
        Assert.Equal(Quaternion.Identity, Transform.Identity.Rotation);
    }

    [Fact]
    public void Identity_Scale_IsOne()
    {
        Assert.Equal(Vector3.One, Transform.Identity.Scale);
    }





}
