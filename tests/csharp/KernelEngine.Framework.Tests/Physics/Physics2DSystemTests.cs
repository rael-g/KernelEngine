using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class Physics2DSystemTests
{
    [Fact]
    public void Update_StepsPhysics_CorrectNumberofTimes()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);

        // dt = 2.5 * 1/60 should result in 2 steps
        system.Update(null!, 2.5f / 60f, null, null);

        physics.Received(2).Step(Physics2DSystem.FixedTimestep);
    }

    [Fact]
    public void Update_CapsSteps_WhenDeltaTimeIsTooLarge()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);

        // dt = 1.0s should result in many steps, but capped at 8
        system.Update(null!, 1.0f, null, null);

        physics.Received(8).Step(Physics2DSystem.FixedTimestep);
    }

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
    public void Update_SyncsTransforms()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);
        var body = new DynamicBody2D();
        var handle = new BodyHandle2D(42);
        
        // Setup body mock
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.TransformComponentId.Returns(1u);

        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        Physics2DContext.Set(physics, system);
        
        body.Initialize(1, world, "body");
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(body, null);

        // State to sync
        physics.GetBodyState(handle).Returns(new BodyState2D { Position = new Vector2(100, 200), Angle = 0.5f });

        // Update with enough time for 1 step
        system.Update(null!, Physics2DSystem.FixedTimestep, null, null);

        Assert.Equal(100f, body.LocalTransform.Position.X);
        Assert.Equal(200f, body.LocalTransform.Position.Y);
        // Rotation check
        var q = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, 0.5f);
        Assert.Equal(q.W, body.LocalTransform.Rotation.W, 5);
        
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void Unregister_StopsSyncing()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);
        var body = new DynamicBody2D();
        var handle = new BodyHandle2D(42);
        
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        Physics2DContext.Set(physics, system);
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(body, null);

        system.Unregister(body);
        
        physics.GetBodyState(handle).Returns(new BodyState2D { Position = new Vector2(999, 999) });
        system.Update(null!, Physics2DSystem.FixedTimestep, null, null);

        Assert.NotEqual(999f, body.LocalTransform.Position.X);
        Physics2DContext.Set(null, null);
    }
}
