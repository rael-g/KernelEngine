using KernelEngine.Framework;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class NodeFrameworkTests
{
    [Fact]
    public void MeshNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new MeshNode(), "Mesh");
        Assert.NotNull(node);
    }

    [Fact]
    public void CameraNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new CameraNode(), "Camera");
        Assert.NotNull(node);
    }

    [Fact]
    public void LightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new LightNode(), "Light");
        Assert.NotNull(node);
    }

    [Fact]
    public void PointLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new PointLightNode(), "PointLight");
        Assert.NotNull(node);
    }

    [Fact]
    public void SpotLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new SpotLightNode(), "SpotLight");
        Assert.NotNull(node);
    }

    [Fact]
    public void SkyboxNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var scene = new Scene(world); var node = scene.AddNode(new SkyboxNode(), "Skybox");
        Assert.NotNull(node);
    }
}
