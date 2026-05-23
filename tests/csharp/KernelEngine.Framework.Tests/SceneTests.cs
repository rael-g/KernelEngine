using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class SceneTests
{
    [Fact]
    public void Root_ReturnsValidNode()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var Tree = new Tree(world);
        
        Assert.NotNull(Tree.Root);
        Assert.Equal("Root", Tree.Root.Name);
    }

    [Fact]
    public void AddNode_CreatesChildOfRootByDefault()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var Tree = new Tree(world);
        
        var node = Tree.AddNode("Child");
        Assert.NotNull(node);
        Assert.Equal("Child", node.Name);
        // We can't easily check parent from Node yet without more API, 
        // but we can check if it was created successfully.
    }

    [Fact]
    public void AddNode_WithParent_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var Tree = new Tree(world);
        
        var parent = Tree.AddNode("Parent");
        var child = Tree.AddNode("Child", parent);
        
        Assert.NotNull(child);
        Assert.Equal("Child", child.Name);
    }

    [Fact]
    public void DestroyNode_Works()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var Tree = new Tree(world);
        
        var node = Tree.AddNode("ToDestroy");
        Tree.DestroyNode(node);
        
        // After destruction, getting the node from registry should fail or the entity should be invalid.
        // Node.Unregister is called, so Node.FromEntity should return null.
        Assert.Null(Node.FromEntity(node.Entity));
    }
}
