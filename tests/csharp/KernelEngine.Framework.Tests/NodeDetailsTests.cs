using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class NodeDetailsTests
{
    private class TestNode : Node
    {
        public int AwakeCount;
        public int StartCount;
        public int UpdateCount;
        public int LateUpdateCount;
        public int InputCount;

        protected override void Awake() => AwakeCount++;
        protected override void Start() => StartCount++;
        protected override void Update(float dt) => UpdateCount++;
        protected override void LateUpdate(float dt) => LateUpdateCount++;
        protected override void OnInput(ref InputEvent evt) => InputCount++;

        public new Span<T> AddComponent<T>(uint cid) where T : unmanaged => base.AddComponent<T>(cid);
        public new Span<T> GetComponent<T>(uint cid) where T : unmanaged => base.GetComponent<T>(cid);
        public new void RemoveComponent(uint cid) => base.RemoveComponent(cid);
    }

    [Fact]
    public void Properties_WorkCorrectly()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var node = new TestNode();
        tree.AddNode(node, "Test");

        // 1. Transform
        var t = new Transform { Position = new Vector3(1, 2, 3), Rotation = Quaternion.Identity, Scale = Vector3.One };
        node.LocalTransform = t;
        
        var t2 = node.LocalTransform;
        Assert.Equal(t.Position, t2.Position);
        Assert.Equal(Matrix4x4.Identity, node.WorldMatrix); // System hasn't run yet

        // 2. Hierarchy
        var child = tree.AddNode("Child", node);
        Assert.Same(node, child.Parent);
        Assert.Same(child, node.FirstChild);
        Assert.Null(child.NextSibling);

        var sibling = tree.AddNode("Sibling", node);
        // AddNode prepends, so sibling is now FirstChild
        Assert.Same(sibling, node.FirstChild);
        Assert.Same(child, sibling.NextSibling);

        // 3. ECS Helpers
        var cid = world.Registry.RegisterComponent<HierarchyComponent>("Dummy");
        var comp = node.AddComponent<HierarchyComponent>(cid);
        Assert.False(comp.IsEmpty);
        
        var comp2 = node.GetComponent<HierarchyComponent>(cid);
        Assert.False(comp2.IsEmpty);

        node.RemoveComponent(cid);
        Assert.True(node.GetComponent<HierarchyComponent>(cid).IsEmpty);
    }

    [Fact]
    public void Lifecycle_MethodsAndEvents_AreCalled()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var node = new TestNode();
        bool awakeEvent = false, startEvent = false;
        float updateDt = 0, lateUpdateDt = 0;
        bool inputEvent = false;

        node.OnAwakeEvent = () => awakeEvent = true;
        node.OnStart = () => startEvent = true;
        node.OnUpdate = dt => updateDt = dt;
        node.OnLateUpdate = dt => lateUpdateDt = dt;
        node.OnInputEvent = (ref InputEvent e) => inputEvent = true;

        tree.AddNode(node, "L");
        
        // 1. Awake + Start
        tree.TickAwakeAndStart();
        Assert.Equal(1, node.AwakeCount);
        Assert.Equal(1, node.StartCount);
        Assert.True(awakeEvent);
        Assert.True(startEvent);

        // 2. Update
        tree.TickUpdate(0.5f);
        Assert.Equal(1, node.UpdateCount);
        Assert.Equal(0.5f, updateDt);

        // 3. LateUpdate
        tree.TickLateUpdate(0.7f);
        Assert.Equal(1, node.LateUpdateCount);
        Assert.Equal(0.7f, lateUpdateDt);

        // 4. Input
        var ev = new InputEvent { Kind = InputEventKind.KeyDown };
        tree.DispatchInput(new[] { ev });
        Assert.Equal(1, node.InputCount);
        Assert.True(inputEvent);
    }

    [Fact]
    public void StaticRegistry_FunctionsCorrectly()
    {
        Node.ClearRegistry();
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        
        var node = new Node(12345, world, "RegistryTest");
        
        Assert.Same(node, Node.FromEntity(12345));
        
        Node.Unregister(12345);
        Assert.Null(Node.FromEntity(12345));
    }
}
