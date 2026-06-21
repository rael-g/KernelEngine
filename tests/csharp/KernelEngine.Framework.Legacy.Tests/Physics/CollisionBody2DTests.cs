using System.Numerics;
using Xunit;
using NSubstitute;

namespace KernelEngine.Framework.Legacy.Tests;

public class CollisionBody2DTests
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

    private (IPhysics2D Physics, Physics2DSystem System, IWorld World) SetupContext()
    {
        var physics = Substitute.For<IPhysics2D>();
        var system = new Physics2DSystem(physics);
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.TransformComponentId.Returns(1u);
        Physics2DContext.Set(physics, system);
        return (physics, system, world);
    }

    [Fact]
    public void Position_SetsPending_BeforeStart()
    {
        var player = new DynamicBody2D();
        var pos = new Vector2(1, 2);
        player.Position = pos;
        Assert.Equal(pos, player.Position);
    }

    [Fact]
    public void Position_SetsLive_AfterStart()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        var pos = new Vector2(1, 2);
        
        player.Initialize(1, world, "player");
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        startMethod!.Invoke(player, null);

        player.Position = pos;

        physics.Received(1).SetBodyPosition(handle, pos, Arg.Any<float>());
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void Rotation_SetsPending_BeforeStart()
    {
        var player = new DynamicBody2D();
        player.Rotation = 1.5f;
        Assert.Equal(1.5f, player.Rotation);
    }

    [Fact]
    public void LinearVelocity_SetsPending_BeforeStart()
    {
        var player = new DynamicBody2D();
        var vel = new Vector2(5, 5);
        player.LinearVelocity = vel;
        Assert.Equal(vel, player.LinearVelocity);
    }

    [Fact]
    public void Teleport_CallsNative()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        player.Teleport(new Vector2(10, 10), 1.0f);

        physics.Received(1).SetBodyPosition(handle, new Vector2(10, 10), 1.0f);
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void AddCollider_AddsCircle_AfterStart()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        player.AddCollider(new CircleShape2D(5f));

        physics.Received(1).AddCircleFixture(handle, 5f, 1f, 0.3f, 0f);
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void AddCollider_AddsBox_AfterStart()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        player.AddCollider(new RectangleShape2D(new Vector2(1, 1)));

        physics.Received(1).AddBoxFixture(handle, new Vector2(1, 1), 1f, 0.3f, 0f);
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void Start_RegistersWithSystem()
    {
        var (physics, system, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        // We check internal registry if possible, or just verify it didn't throw and body is valid
        Assert.Equal(handle, player.Body);
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void ApplyImpulse_CallsNative()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        player.ApplyImpulse(new Vector2(10, 0));

        physics.Received(1).ApplyImpulse(handle, new Vector2(10, 0));
        Physics2DContext.Set(null, null);
    }

    [Fact]
    public void OnDestroy_DestroysNativeBody()
    {
        var (physics, _, world) = SetupContext();
        var player = new DynamicBody2D();
        player.Initialize(1, world, "player");

        var handle = new BodyHandle2D(42);
        physics.CreateBody(Arg.Any<BodyType2D>(), Arg.Any<Vector2>()).Returns(handle);
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(player, null);

        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        onDestroyMethod!.Invoke(player, null);

        physics.Received(1).DestroyBody(handle);
        Assert.False(player.Body.IsValid);
        Physics2DContext.Set(null, null);
    }
}
