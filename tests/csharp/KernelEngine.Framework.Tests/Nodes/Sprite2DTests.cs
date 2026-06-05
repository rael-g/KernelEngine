using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class Sprite2DTests
{
    private class FakeRegistry : IEcsRegistry
    {
        private readonly Dictionary<(ulong, uint), object> _data = new();
        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 1u;
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
    public void Size_UpdatesLocalTransform()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        
        sprite.Size = new Vector2(5, 10);

        Assert.Equal(5f, sprite.LocalTransform.Scale.X);
        Assert.Equal(10f, sprite.LocalTransform.Scale.Y);
    }

    [Fact]
    public void Position2D_UpdatesLocalTransform()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        sprite.LocalTransform = sprite.LocalTransform with { Position = new Vector3(0, 0, 5) };
        
        sprite.Position2D = new Vector2(100, 200);

        Assert.Equal(100f, sprite.LocalTransform.Position.X);
        Assert.Equal(200f, sprite.LocalTransform.Position.Y);
        Assert.Equal(5f, sprite.LocalTransform.Position.Z);
    }

    [Fact]
    public void Size_Get_ReturnsCorrectValue()
    {
        var sprite = new Sprite2D { Size = new Vector2(3, 4) };
        // We need a world for LocalTransform to work, but let's see if it works without it 
        // if we just set it. Wait, Node.LocalTransform depends on World.Registry.
        
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        sprite.Initialize(1, world, "s");
        
        sprite.Size = new Vector2(3, 4);
        Assert.Equal(new Vector2(3, 4), sprite.Size);
    }

    [Fact]
    public void Position2D_Get_ReturnsCorrectValue()
    {
        var sprite = new Sprite2D();
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        sprite.Initialize(1, world, "s");
        
        sprite.Position2D = new Vector2(7, 8);
        Assert.Equal(new Vector2(7, 8), sprite.Position2D);
    }

    [Fact]
    public void Start_AppliesStagedSize()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);
        world.GetOrRegisterComponentId<MeshComponent>(Arg.Any<string>()).Returns(2u);

        var sprite = new Sprite2D();
        sprite.Size = new Vector2(42, 42); // Staged, no world yet
        
        sprite.Initialize(1, world, "sprite");

        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(sprite, null);

        Assert.Equal(42f, sprite.LocalTransform.Scale.X);
    }
}
