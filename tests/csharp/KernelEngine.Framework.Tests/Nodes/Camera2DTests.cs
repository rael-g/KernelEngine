using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class Camera2DTests
{
    [Fact]
    public void Camera2D_InitializesWith2DDefaults()
    {
        var cam = new Camera2D();
        Assert.True(cam.Orthographic);
        Assert.Equal(0.1f, cam.Near);
        Assert.Equal(100f, cam.Far);
        Assert.Equal(5f, cam.OrthographicSize);
    }

    [Fact]
    public void Camera2D_Start_SetsDefaultZPosition()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var cam = new Camera2D();
        tree.AddNode(cam, "Cam");
        tree.TickAwakeAndStart();

        Assert.Equal(10f, cam.LocalTransform.Position.Z);
    }

    [Fact]
    public void Camera2D_Start_DoesNotOverrideUserPosition()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var cam = new Camera2D();
        tree.AddNode(cam, "Cam");
        
        // Node is now bound to world, so setter works
        cam.LocalTransform = cam.LocalTransform with { Position = new Vector3(0, 0, 50) };
        
        tree.TickAwakeAndStart();

        Assert.Equal(50f, cam.LocalTransform.Position.Z);
    }
}
