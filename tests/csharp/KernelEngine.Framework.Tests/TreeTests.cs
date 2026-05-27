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

    private class InputMockNode(Func<bool> onInput) : Node
    {
        protected override void OnInput(ref InputEvent evt)
        {
            if (onInput()) evt.Consume();
        }
    }
}
