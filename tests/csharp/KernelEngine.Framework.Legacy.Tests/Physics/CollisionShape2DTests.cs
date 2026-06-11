using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class CollisionShape2DTests
{
    private class FakeRegistry : IEcsRegistry
    {
        public Dictionary<(ulong, uint), object> Data = new();

        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 0;
        public bool TryLookupComponent(string name, out uint componentId) { componentId = 0; return false; }
        public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged => new T[1];
        public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged 
        {
            if (Data.TryGetValue((entity, componentId), out var val) && val is T[] arr) return arr;
            return Span<T>.Empty;
        }
        public void RemoveComponent(ulong entity, uint componentId) { }
        public bool HasComponent(ulong entity, uint componentId) => true;
        public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged => default;
    }

    [Fact]
    public void Start_CallsAddCollider_OnAncestorBody()
    {
        var registry = new FakeRegistry();
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(registry);
        world.HierarchyComponentId.Returns(1u);

        var body = new DynamicBody2D();
        body.Initialize(10, world, "body");

        var shapeNode = new CollisionShape2D();
        shapeNode.Initialize(11, world, "shape");
        shapeNode.Shape = new CircleShape2D(1f);

        // Setup hierarchy in registry: 11's parent is 10
        registry.Data[(11, 1)] = new HierarchyComponent[] { new() { Parent = 10 } };

        var startMethod = typeof(CollisionShape2D).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(shapeNode, null);

        var pending = (System.Collections.IEnumerable)typeof(CollisionBody2D).GetField("_pendingFixtures", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance)!.GetValue(body)!;
        Assert.NotEmpty(pending);
    }

    [Fact]
    public void Start_Throws_WhenNoAncestorBody()
    {
        var registry = new FakeRegistry();
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(registry);
        world.HierarchyComponentId.Returns(1u);

        var shapeNode = new CollisionShape2D { Name = "test_shape" };
        shapeNode.Initialize(11, world, "shape");
        shapeNode.Shape = new CircleShape2D(1f);

        var startMethod = typeof(CollisionShape2D).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        
        var ex = Assert.Throws<System.Reflection.TargetInvocationException>(() => startMethod!.Invoke(shapeNode, null));
        Assert.IsType<InvalidOperationException>(ex.InnerException);
    }

    [Fact]
    public void Start_DoesNothing_WhenShapeIsNull()
    {
        var shapeNode = new CollisionShape2D();
        var startMethod = typeof(CollisionShape2D).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        
        // Should not throw even if no parent
        startMethod!.Invoke(shapeNode, null);
    }
}
