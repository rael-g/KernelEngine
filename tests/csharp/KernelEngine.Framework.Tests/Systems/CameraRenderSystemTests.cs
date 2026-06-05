using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using KernelEngine.Framework.Internal;

namespace KernelEngine.Framework.Tests;

public class CameraRenderSystemTests
{
    private class FakeRegistry : IEcsRegistry
    {
        public readonly Dictionary<(ulong, uint), object> Data = new();
        public ulong[] CurrentQueryEntities = Array.Empty<ulong>();

        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 0;
        public Span<T> AddComponent<T>(ulong entity, uint componentId) where T : unmanaged => GetComponent<T>(entity, componentId);
        public Span<T> GetComponent<T>(ulong entity, uint componentId) where T : unmanaged 
        {
            if (!Data.TryGetValue((entity, componentId), out var val)) return Span<T>.Empty;
            return (T[])val;
        }
        public void RemoveComponent(ulong entity, uint componentId) { }
        public bool HasComponent(ulong entity, uint componentId) => true;
        public EcsQuery<T> Query<T>(uint componentId) where T : unmanaged 
        {
            var data = new T[CurrentQueryEntities.Length];
            for (int i = 0; i < CurrentQueryEntities.Length; i++)
            {
                if (Data.TryGetValue((CurrentQueryEntities[i], componentId), out var val) && val is T[] arr)
                    data[i] = arr[0];
            }
            return new EcsQuery<T>(CurrentQueryEntities, data);
        }
        
        public void SetComponent<T>(ulong entity, uint componentId, T val) where T : unmanaged
        {
            Data[(entity, componentId)] = new T[] { val };
        }
    }

    [Fact]
    public void Update_SetsCameraInPacket()
    {
        var registry = new FakeRegistry();
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(registry);
        
        uint cameraCid = 10;
        uint transformCid = 11;
        
        registry.CurrentQueryEntities = new ulong[] { 1 };
        registry.SetComponent(1, cameraCid, new CameraComponent { 
            Orthographic = 1, OrthographicSize = 5f, Near = 0.1f, Far = 100f 
        });
        registry.SetComponent(1, transformCid, new TransformComponent { 
            WorldMatrix = Matrix4x4.Identity, Position = Vector3.Zero 
        });

        var packet = Substitute.For<IFramePacket>();
        var system = new CameraRenderSystem(cameraCid, transformCid);

        system.Update(world, 0.016f, packet);

        packet.Received(1).SetCamera(Arg.Any<Matrix4x4>(), Arg.Any<Matrix4x4>(), Arg.Any<Vector3>());
    }

    [Fact]
    public void Update_DoesNothing_WhenNoPacket()
    {
        var system = new CameraRenderSystem(1, 2);
        system.Update(null!, 0.016f, null);
    }

    [Fact]
    public void Update_ReturnsEarly_WhenNoCameras()
    {
        var registry = new FakeRegistry();
        registry.CurrentQueryEntities = Array.Empty<ulong>();
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(registry);

        var system = new CameraRenderSystem(1, 2);
        var packet = Substitute.For<IFramePacket>();

        system.Update(world, 0.016f, packet);

        packet.DidNotReceiveWithAnyArgs().SetCamera(default, default, default);
    }

    [Fact]
    public void GetAccess_ReturnsCorrectCids()
    {
        var system = new CameraRenderSystem(10, 11);
        var access = system.GetAccess();
        Assert.Contains(10u, access.Reads);
        Assert.Contains(11u, access.Reads);
        Assert.Empty(access.Writes);
    }
}
