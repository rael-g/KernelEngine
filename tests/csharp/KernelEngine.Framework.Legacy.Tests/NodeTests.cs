using System.Numerics;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

using KernelEngine.Framework.Legacy.Native;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class NodeTests
{
    public NodeTests()
    {
        FrameworkBackends.Default ??= new NativeFrameworkBackendFactory();
    }

    private Tree SetupTree(World world)
    {
        Node.ClearRegistry();
        return new Tree(world);
    }

    [Fact]
    public void GetNode_RelativePath_Child()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);

        Assert.Same(child, parent.GetNode("Child"));
    }

    [Fact]
    public void GetNode_RelativePath_Grandchild()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        var grandchild = tree.AddNode("Grandchild", child);

        Assert.Same(grandchild, parent.GetNode("Child/Grandchild"));
    }

    [Fact]
    public void GetNode_RelativePath_Parent()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);

        Assert.Same(parent, child.GetNode(".."));
    }

    [Fact]
    public void GetNode_RelativePath_Sibling()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        var sibling = tree.AddNode("Sibling", parent);

        Assert.Same(sibling, child.GetNode("../Sibling"));
    }

    [Fact]
    public void GetNode_RelativePath_Self()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);

        Assert.Same(child, child.GetNode("."));
    }

    [Fact]
    public void GetNode_RelativePath_Empty()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = SetupTree(world);
        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);

        Assert.Same(child, child.GetNode(""));
    }

    [Fact]
    public void LocalTransform_Setter_NoOpWhenNoWorld()
    {
        var node = new TestNode();
        node.LocalTransform = new Transform { Position = Vector3.One };
        Assert.Equal(Vector3.Zero, node.LocalTransform.Position);
    }

    [Fact]
    public void TickAwakeAndStart_OnlyRunsAwakeOnce()
    {
        int awakeCount = 0;
        var node = new TestNode();
        node.OnAwakeEvent = () => awakeCount++;

        node.TickAwakeAndStart();
        node.TickAwakeAndStart();

        Assert.Equal(1, awakeCount);
    }

    [Fact]
    public void TickAwakeAndStart_OnlyRunsStartOnce()
    {
        int startCount = 0;
        var node = new TestNode();
        node.OnStart = () => startCount++;

        node.TickAwakeAndStart();
        node.TickAwakeAndStart();

        Assert.Equal(1, startCount);
    }

    [Fact]
    public void TickUpdate_CallsDelegate()
    {
        float receivedDt = 0;
        var node = new TestNode();
        node.OnUpdate = (dt) => receivedDt = dt;

        node.TickUpdate(0.5f);
        Assert.Equal(0.5f, receivedDt);
    }

    [Fact]
    public void SnapshotRegistry_ReturnsCurrentNodes()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        tree.AddNode("N1");
        tree.AddNode("N2");

        var snapshot = Node.SnapshotRegistry();
        Assert.Equal(3, snapshot.Count); // Root + N1 + N2
    }

    private class TestNode : Node { }
}
