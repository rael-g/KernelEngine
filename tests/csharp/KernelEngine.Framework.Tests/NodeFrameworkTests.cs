using KernelEngine.Framework;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

public class NodeFrameworkTests
{
    [Fact]
    public void MeshNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new MeshNode(), "Mesh");
        Assert.NotNull(node);
    }

    [Fact]
    public void CameraNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new CameraNode(), "Camera");
        Assert.NotNull(node);
    }

    [Fact]
    public void LightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new LightNode(), "Light");
        Assert.NotNull(node);
    }

    [Fact]
    public void PointLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new PointLightNode(), "PointLight");
        Assert.NotNull(node);
    }

    [Fact]
    public void SpotLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new SpotLightNode(), "SpotLight");
        Assert.NotNull(node);
    }

    [Fact]
    public void SkyboxNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode(new SkyboxNode(), "Skybox");
        Assert.NotNull(node);
    }
}
