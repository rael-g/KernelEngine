using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class DirectionalLightTests
{
    private class FakeRegistry : IEcsRegistry
    {
        private readonly Dictionary<(ulong, uint), object> _data = new();
        public ulong CreateEntity() => 0;
        public void DestroyEntity(ulong entity) { }
        public uint RegisterComponent<T>(string name) where T : unmanaged => 0;
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
    public void Properties_WorkBeforeStart()
    {
        var light = new DirectionalLight();
        light.Direction = Vector3.UnitX;
        light.Color = Vector3.Zero;
        light.Intensity = 5f;

        Assert.Equal(Vector3.UnitX, light.Direction);
        Assert.Equal(Vector3.Zero, light.Color);
        Assert.Equal(5f, light.Intensity);
    }

    [Fact]
    public void Properties_SyncAfterStart()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.GetOrRegisterComponentId<LightComponent>("LightComponent").Returns(10u);

        var light = new DirectionalLight();
        light.Initialize(1, world, "light");
        
        var startMethod = typeof(Node).GetMethod("Start", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
        startMethod!.Invoke(light, null);

        light.Direction = Vector3.UnitZ;
        light.Intensity = 10f;

        var slot = world.Registry.GetComponent<LightComponent>(1, 10u);
        Assert.Equal(1f, slot[0].DirZ);
        Assert.Equal(10f, slot[0].Intensity);
    }
}
