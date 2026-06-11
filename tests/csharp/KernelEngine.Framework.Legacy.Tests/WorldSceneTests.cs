using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class WorldSceneTests
{
    [Fact]
    public void World_CanBeCreatedAndDestroyed()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        Assert.NotNull(new Tree(world).Root);
    }

    [Fact]
    public void World_CanCreateNodes()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = new Tree(world).AddNode("TestNode");
        Assert.NotNull(node);
        Assert.Equal("TestNode", node.Name);
        Assert.NotEqual(0UL, node.Entity);
    }

    [Fact]
    public void World_HierarchyWorks()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var parent = new Tree(world).AddNode("Parent");
        var child = new Tree(world).AddNode("Child", parent);
        
        Assert.Equal(parent.Entity, child.Parent?.Entity);
        Assert.Equal(child.Entity, parent.FirstChild?.Entity);
    }
}
