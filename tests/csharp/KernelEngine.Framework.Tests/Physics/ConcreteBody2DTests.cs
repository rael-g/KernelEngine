using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class ConcreteBody2DTests
{
    private class FakeRegistry : IEcsRegistry
    {
        private readonly Dictionary<(ulong, uint), object> _data = new();
        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 0;
        public bool TryLookupComponent(string name, out uint componentId) { componentId = 0; return false; }
        public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged => GetComponent<T>(entity, componentId);
        public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged 
        {
            if (!_data.TryGetValue((entity, componentId), out var val))
            {
                val = new T[1];
                _data[(entity, componentId)] = val;
            }
            return (T[])val;
        }
        public void RemoveComponent(ulong entity, uint componentId) { }
        public bool HasComponent(ulong entity, uint componentId) => true;
        public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged => default;
    }

    [Fact]
    public void StaticBody2D_UsesCorrectBodyType()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        Physics2DContext.Set(physics, system);
        
        var body = new StaticBody2D();
        body.Initialize(1, world, "static");
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(body, null);

        physics.Received(1).CreateBody(BodyType2D.Static, Arg.Any<System.Numerics.Vector2>());
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void KinematicBody2D_UsesCorrectBodyType()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        Physics2DContext.Set(physics, system);
        
        var body = new KinematicBody2D();
        body.Initialize(1, world, "kinematic");
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(body, null);

        physics.Received(1).CreateBody(BodyType2D.Kinematic, Arg.Any<System.Numerics.Vector2>());
        Physics2DContext.Set(null, null);
    }
}
