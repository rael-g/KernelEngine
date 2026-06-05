using KernelEngine.Framework;
using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class TreeTests
{
    [Fact]
    public void DestroyNode_RemovesFromHierarchyAndEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        
        Assert.NotNull(parent.FirstChild);
        Assert.Equal(child.Entity, parent.FirstChild.Entity);

        tree.DestroyNode(child);
        
        Assert.Null(parent.FirstChild);
        // Verify entity is destroyed in ECS (registry.GetComponent should be empty)
        var h = world.Registry.GetComponent<HierarchyComponent>(child.Entity, world.HierarchyComponentId);
        Assert.True(h.IsEmpty);
    }

    [Fact]
    public void DestroyNode_Recursive_RemovesDescendants()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var parent = tree.AddNode("Parent");
        var child = tree.AddNode("Child", parent);
        var grandChild = tree.AddNode("GrandChild", child);

        tree.DestroyNode(parent);

        Assert.True(world.Registry.GetComponent<HierarchyComponent>(parent.Entity, world.HierarchyComponentId).IsEmpty);
        Assert.True(world.Registry.GetComponent<HierarchyComponent>(child.Entity, world.HierarchyComponentId).IsEmpty);
        Assert.True(world.Registry.GetComponent<HierarchyComponent>(grandChild.Entity, world.HierarchyComponentId).IsEmpty);
    }

    [Fact]
    public void DispatchInput_VisitsNodesAndStopsOnConsume()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        int visitCount = 0;
        var n1 = tree.AddNode(new InputMockNode(() => { visitCount++; return false; }), "N1");
        var n2 = tree.AddNode(new InputMockNode(() => { visitCount++; return true; }), "N2"); // Consumes
        var n3 = tree.AddNode(new InputMockNode(() => { visitCount++; return false; }), "N3");

        var events = new[] { new InputEvent { Kind = InputEventKind.KeyDown } };
        tree.DispatchInput(events);

        Assert.Equal(2, visitCount); // Root (no handler) -> N2 (consumes) -> N1 (prepended, so N2 is first sibling?)
        // Wait, AddNode prepends.
        // Root children: N3 (added last, so first), N2 (added second, so middle), N1 (added first, so last).
        // Pre-order: Root -> N3 -> N2 -> N1.
        // If N2 consumes, N1 is not visited.
        // Wait, if N3 is first, and it doesn't consume, then N2 is visited.
        // If N2 consumes, N1 is NOT visited.
        // Total visits: Root(0) + N3(1) + N2(1) = 2.
    }

    [Fact]
    public void FindNode_ByName_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("Child");
        
        Assert.Same(child, tree.FindNode("Child"));
    }

    [Fact]
    public void FindNode_ByPath_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("A");
        var grandchild = tree.AddNode("B", child);
        
        Assert.Same(grandchild, tree.FindNode("A/B"));
        Assert.Same(grandchild, tree.FindNode("/A/B"));
    }

    [Fact]
    public void FindNode_Recursive_Works()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var child = tree.AddNode("A");
        var grandchild = tree.AddNode("Target", child);
        
        Assert.Same(grandchild, tree.FindNode("Target"));
    }

    [Fact]
    public void AddNode_HandlesNameCollisions()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        
        var n1 = tree.AddNode("Test");
        var n2 = tree.AddNode("Test");
        var n3 = tree.AddNode("Test");

        Assert.Equal("Test", n1.Name);
        Assert.Equal("Test_2", n2.Name);
        Assert.Equal("Test_3", n3.Name);
    }

    [Fact]
    public void DispatchInputActions_PropagatesToChildren()
    {
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

    // ── Phase 4 of ECS-pure nodes: tree.WrapEntity<T> ───────────────────────
    //
    // The component-driven SceneLoader (Phase 2) only writes data — it doesn't
    // create C# wrapper instances. Game code calls WrapEntity for each entity
    // it wants Update/OnInput hooks on. Matches design decision #1: wrappers
    // materialise explicitly, not for every entity in the scene.

    private class FakePaddle : Node { public int UpdateCalls; protected override void Update(float dt) => UpdateCalls++; }

    [Fact]
    public void WrapEntity_AssignsTypedWrapperToExistingEntity()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        // Simulate the SceneLoader: create an entity through the native tree;
        // no C# wrapper exists yet.
        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);

        var wrapper = tree.WrapEntity<FakePaddle>(raw);

        Assert.Same(wrapper, Node.FromEntity(raw));
        Assert.Equal(raw, wrapper.Entity);
        Assert.Equal("Paddle", wrapper.Name);
    }

    [Fact]
    public void WrapEntity_Idempotent_ReturnsExistingWrapper()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var raw = tree.NativeWrapper.CreateNode("Paddle", tree.Root.Entity);
        var first  = tree.WrapEntity<FakePaddle>(raw);
        var second = tree.WrapEntity<FakePaddle>(raw);
        Assert.Same(first, second);
    }

    [Fact]
    public void WrapEntity_InvalidEntity_Throws()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        Assert.Throws<ArgumentException>(() => tree.WrapEntity<FakePaddle>(0UL));
    }
}
