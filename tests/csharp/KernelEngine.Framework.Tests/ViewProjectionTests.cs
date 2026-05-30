using System.Numerics;
using KernelEngine.Framework.Internal;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class ViewProjectionTests
{
    [Fact]
    public void LookAt_ProducesCorrectViewMatrix()
    {
        var eye = new Vector3(0, 0, 10);
        var target = Vector3.Zero;
        var up = Vector3.UnitY;

        var view = ViewProjection.LookAt(eye, target, up);

        // At eye (0,0,10) looking at (0,0,0): forward (toward target) = (0,0,-1).
        // RH view matrix stores -forward in the z column so view-space z is NEGATIVE for
        // content in front of the camera (matches the [-near,-far] frustum Ortho/Perspective
        // produce). With f=(0,0,-1): -f.Z = +1 → M33 = 1, and dot(f,eye) = -10 → M43 = -10.
        // Origin transforms to view-z = M43 = -10, which Ortho(near=0.1, far=100) maps to
        // NDC z ≈ 0.1 — inside the frustum (correct).

        Assert.Equal(-1, view.M11); // Right.X
        Assert.Equal(1, view.M22);  // Up.Y
        Assert.Equal(1, view.M33);  // -Forward.Z (RH)
        Assert.Equal(-10, view.M43); // +dot(f, eye) (RH) — origin lands at view-z = -10
    }

    [Fact]
    public void Perspective_ZeroToOne_ProducesCorrectMatrix()
    {
        ViewProjection.SetConvention(new NdcConvention(ZeroToOneDepth: true, YFlip: false, LeftHanded: false));
        
        var proj = ViewProjection.Perspective(MathF.PI / 2, 1.0f, 0.1f, 100f);
        
        // f = 1/tan(pi/4) = 1
        Assert.Equal(1.0f, proj.M11);
        Assert.Equal(1.0f, proj.M22);
        Assert.Equal(-1.0f, proj.M34);
        
        // M33 = -far / (far - near) = -100 / 99.9
        Assert.Equal(-100f / 99.9f, proj.M33, 3);
    }

    [Fact]
    public void Perspective_NegOneToOne_ProducesCorrectMatrix()
    {
        ViewProjection.SetConvention(new NdcConvention(ZeroToOneDepth: false, YFlip: false, LeftHanded: false));
        
        var proj = ViewProjection.Perspective(MathF.PI / 2, 1.0f, 0.1f, 100f);
        
        // M33 = -(far + near) / (far - near) = -100.1 / 99.9
        Assert.Equal(-100.1f / 99.9f, proj.M33, 3);
    }

    [Fact]
    public void Ortho_ProducesCorrectMatrix()
    {
        ViewProjection.SetConvention(new NdcConvention(ZeroToOneDepth: true, YFlip: false, LeftHanded: false));
        
        var proj = ViewProjection.Ortho(-10, 10, -10, 10, 0, 100);
        
        // RH ortho + Z ∈ [0, 1] (Vulkan-canonical frontend): view-z ∈ [-near, -far] → clip-z ∈ [0, 1].
        // M33 = -1 / (far - near) = -0.01; M43 = -near / (far - near) = 0 when near = 0.
        Assert.Equal(2f / 20f, proj.M11);
        Assert.Equal(2f / 20f, proj.M22);
        Assert.Equal(-1f / 100f, proj.M33);
        Assert.Equal(0f, proj.M43);
    }
}
