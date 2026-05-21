using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

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

    [Fact]
    public void ToNative_MaintainsValues()
    {
        var t = new Transform
        {
            Position = new Vector3(1, 2, 3),
            Rotation = Quaternion.Identity,
            Scale = Vector3.One
        };
        var native = TransformInterop.ToNative(t);
        Assert.Equal(1.0f, native.position.x);
    }

    [Fact]
    public void ToNative_MaintainsY()
    {
        var t = new Transform { Position = new Vector3(1, 2, 3) };
        var native = TransformInterop.ToNative(t);
        Assert.Equal(2.0f, native.position.y);
    }

    [Fact]
    public void ToNative_MaintainsZ()
    {
        var t = new Transform { Position = new Vector3(1, 2, 3) };
        var native = TransformInterop.ToNative(t);
        Assert.Equal(3.0f, native.position.z);
    }

    [Fact]
    public void FromNative_MaintainsValues()
    {
        var native = new ke_transform
        {
            position = new ke_vec3 { x = 10, y = 20, z = 30 },
            rotation = new ke_quat { x = 0, y = 0, z = 0, w = 1 },
            scale = new ke_vec3 { x = 1, y = 1, z = 1 }
        };
        var t = TransformInterop.FromNative(native);
        Assert.Equal(10.0f, t.Position.X);
    }

    [Fact]
    public void FromNative_MaintainsRotation()
    {
        var native = new ke_transform
        {
            rotation = new ke_quat { x = 0.5f, y = 0.5f, z = 0.5f, w = 0.5f }
        };
        var t = TransformInterop.FromNative(native);
        Assert.Equal(0.5f, t.Rotation.X);
        Assert.Equal(0.5f, t.Rotation.Y);
        Assert.Equal(0.5f, t.Rotation.Z);
        Assert.Equal(0.5f, t.Rotation.W);
    }

    [Fact]
    public void FromNative_MaintainsScale()
    {
        var native = new ke_transform
        {
            scale = new ke_vec3 { x = 2, y = 3, z = 4 }
        };
        var t = TransformInterop.FromNative(native);
        Assert.Equal(2, t.Scale.X);
        Assert.Equal(3, t.Scale.Y);
        Assert.Equal(4, t.Scale.Z);
    }
}
