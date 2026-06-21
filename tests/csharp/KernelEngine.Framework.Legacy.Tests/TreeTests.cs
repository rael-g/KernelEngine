using KernelEngine.Framework.Legacy;
using KernelEngine.Framework.Legacy.Native;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class TreeTests
{
    public TreeTests()
    {
        FrameworkBackends.Default ??= new NativeFrameworkBackendFactory();
    }

    [Fact]
    public void DestroyNode_RemovesFromHierarchy()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        
        tree.DestroyNode(child);
        Assert.Null(parent.FirstChild);
    }

    [Fact]
    public void DestroyNode_RemovesFromEcs()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        
        tree.DestroyNode(child);
        var h = world.Registry.GetComponent<HierarchyComponent>(child.Entity, world.HierarchyComponentId);
        Assert.True(h.IsEmpty);
    }

    [Fact]
    public void DestroyNode_Recursive_RemovesParent()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        tree.AddNode("Child", parent);

        tree.DestroyNode(parent);
        Assert.True(world.Registry.GetComponent<HierarchyComponent>(parent.Entity, world.HierarchyComponentId).IsEmpty);
    }

    [Fact]
    public void DestroyNode_Recursive_RemovesChild()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);

        tree.DestroyNode(parent);
        Assert.True(world.Registry.GetComponent<HierarchyComponent>(child.Entity, world.HierarchyComponentId).IsEmpty);
    }

    [Fact]
    public void DestroyNode_Recursive_RemovesGrandChild()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        var grandChild = tree.AddNode("GrandChild", child);

        tree.DestroyNode(parent);
        Assert.True(world.Registry.GetComponent<HierarchyComponent>(grandChild.Entity, world.HierarchyComponentId).IsEmpty);
    }

    [Fact]
    public void DispatchInput_VisitsNodesAndStopsOnConsume()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        int visitCount = 0;
        tree.AddNode(new InputMockNode(() => { visitCount++; return false; }), "N1");
        tree.AddNode(new InputMockNode(() => { visitCount++; return true; }), "N2"); // Consumes
        tree.AddNode(new InputMockNode(() => { visitCount++; return false; }), "N3");

        var events = new[] { new InputEvent { Kind = InputEventKind.KeyDown } };
        tree.DispatchInput(events);

        Assert.Equal(2, visitCount); 
    }

    [Fact]
    public void FindNode_ByName_Works()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("Child");
        
        Assert.Same(child, tree.FindNode("Child"));
    }

    [Fact]
    public void FindNode_ByPath_Relative()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("A");
        var grandchild = tree.AddNode("B", child);
        
        Assert.Same(grandchild, tree.FindNode("A/B"));
    }

    [Fact]
    public void FindNode_ByPath_Absolute()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("A");
        var grandchild = tree.AddNode("B", child);
        
        Assert.Same(grandchild, tree.FindNode("/A/B"));
    }

    [Fact]
    public void FindNode_Recursive_Works()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("A");
        var grandchild = tree.AddNode("Target", child);
        
        Assert.Same(grandchild, tree.FindNode("Target"));
    }

    [Fact]
    public void AddNode_HandlesNameCollision_First()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        var n1 = tree.AddNode("Test");
        Assert.Equal("Test", n1.Name);
    }

    [Fact]
    public void AddNode_HandlesNameCollision_Second()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        tree.AddNode("Test");
        var n2 = tree.AddNode("Test");
        Assert.Equal("Test_2", n2.Name);
    }

    [Fact]
    public void AddNode_HandlesNameCollision_Third()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        tree.AddNode("Test");
        tree.AddNode("Test");
        var n3 = tree.AddNode("Test");
        Assert.Equal("Test_3", n3.Name);
    }

    [Fact]
    public void DispatchInputActions_PropagatesToChildren()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        bool called = false;
        var node = new InputActionMockNode(() => { called = true; return false; });
        tree.AddNode(node, "act");

        var list = new List<InputActionEvent> { new InputActionEvent { ActionId = 1 } };
        tree.DispatchInputActions(list);

        Assert.True(called);
    }

    private class InputMockNode(Func<bool> onInput) : Node
    {
        protected override void OnInput(ref InputEvent evt)
        {
            if (onInput()) evt.Consume();
        }
    }

    private class InputActionMockNode(Func<bool> onInput) : Node
    {
        protected override void OnInputAction(ref InputActionEvent evt)
        {
            if (onInput()) evt.Consume();
        }
    }

    private class FakePaddle : Node { public int UpdateCalls; protected override void Update(float dt) => UpdateCalls++; }

    [Fact]
    public void WrapEntity_AssignsWrapperToRegistry()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);
        var wrapper = tree.WrapEntity<FakePaddle>(raw);

        Assert.Same(wrapper, Node.FromEntity(raw));
    }

    [Fact]
    public void WrapEntity_AssignsEntityId()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);
        var wrapper = tree.WrapEntity<FakePaddle>(raw);

        Assert.Equal(raw, wrapper.Entity);
    }

    [Fact]
    public void WrapEntity_AssignsName()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);
        var wrapper = tree.WrapEntity<FakePaddle>(raw);

        Assert.Equal("Paddle", wrapper.Name);
    }

    [Fact]
    public void WrapEntity_Idempotent_ReturnsExistingWrapper()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);
        var first  = tree.WrapEntity<FakePaddle>(raw);
        var second = tree.WrapEntity<FakePaddle>(raw);
        Assert.Same(first, second);
    }

    [Fact]
    public void TickUpdate_CallsUpdateOnWrappers()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var paddle = new FakePaddle();
        tree.AddNode(paddle, "P");
        
        tree.TickUpdate(0.1f);
        Assert.Equal(1, paddle.UpdateCalls);
    }
}
