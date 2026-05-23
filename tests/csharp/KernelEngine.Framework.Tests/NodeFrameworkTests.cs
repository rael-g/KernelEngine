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
        
        var Tree = new Tree(world); var node = Tree.AddNode(new MeshRenderer(), "Mesh");
        Assert.NotNull(node);
    }

    [Fact]
    public void CameraNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var Tree = new Tree(world); var node = Tree.AddNode(new Camera(), "Camera");
        Assert.NotNull(node);
    }

    [Fact]
    public void LightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var Tree = new Tree(world); var node = Tree.AddNode(new DirectionalLight(), "Light");
        Assert.NotNull(node);
    }

    [Fact]
    public void PointLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var Tree = new Tree(world); var node = Tree.AddNode(new PointLight(), "PointLightData");
        Assert.NotNull(node);
    }

    [Fact]
    public void SpotLightNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var Tree = new Tree(world); var node = Tree.AddNode(new SpotLight(), "SpotLightData");
        Assert.NotNull(node);
    }

    [Fact]
    public void SkyboxNode_CanBeAdded()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var Tree = new Tree(world); var node = Tree.AddNode(new Skybox(), "Skybox");
        Assert.NotNull(node);
    }
}
