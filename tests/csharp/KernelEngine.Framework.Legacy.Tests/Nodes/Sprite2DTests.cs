using System.Numerics;
using Xunit;
using NSubstitute;

namespace KernelEngine.Framework.Legacy.Tests;

public class Sprite2DTests
{
    private class FakeRegistry : IEcsRegistry
    {
        private readonly Dictionary<(ulong, uint), object> _data = new();
        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 1u;
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
    public void Size_UpdatesLocalTransform_ScaleX()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        
        sprite.Size = new Vector2(5, 10);
        Assert.Equal(5f, sprite.LocalTransform.Scale.X);
    }

    [Fact]
    public void Size_UpdatesLocalTransform_ScaleY()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        
        sprite.Size = new Vector2(5, 10);
        Assert.Equal(10f, sprite.LocalTransform.Scale.Y);
    }

    [Fact]
    public void Position2D_UpdatesLocalTransform_PosX()
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
    }

    [Fact]
    public void Position2D_UpdatesLocalTransform_PosY()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        sprite.LocalTransform = sprite.LocalTransform with { Position = new Vector3(0, 0, 5) };
        
        sprite.Position2D = new Vector2(100, 200);
        Assert.Equal(200f, sprite.LocalTransform.Position.Y);
    }

    [Fact]
    public void Position2D_UpdatesLocalTransform_PosZ()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var sprite = new Sprite2D();
        sprite.Initialize(1, world, "sprite");
        sprite.LocalTransform = sprite.LocalTransform with { Position = new Vector3(0, 0, 5) };
        
        sprite.Position2D = new Vector2(100, 200);
        Assert.Equal(5f, sprite.LocalTransform.Position.Z);
    }

    [Fact]
    public void Size_Get_ReturnsCorrectValue()
    {
        var sprite = new Sprite2D();
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
}
