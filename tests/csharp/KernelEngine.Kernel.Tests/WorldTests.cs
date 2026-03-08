using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class WorldTests
{
    [Fact]
    public void World_CanBeCreatedAndDestroyed()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        Assert.NotNull(world.Scene.Root);
    }

    [Fact]
    public void World_CanCreateNodes()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = world.Scene.AddNode("TestNode");
        Assert.NotNull(node);
        Assert.Equal("TestNode", node.Name);
        Assert.NotEqual(0UL, node.Entity);
    }

    [Fact]
    public void World_HierarchyWorks()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var parent = world.Scene.AddNode("Parent");
        var child = world.Scene.AddNode("Child", parent);
        
        Assert.Equal(parent.Entity, child.Parent?.Entity);
        Assert.Equal(child.Entity, parent.FirstChild?.Entity);
    }
}
