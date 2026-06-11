using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy.Tests;

public class MoreLightsTests
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
    public void PointLight_SyncsAfterStart_Radius()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent").Returns(10u);

        var light = new PointLight();
        light.Initialize(1, world, "light");
        
        light.TickAwakeAndStart();

        light.Radius = 50f;
        var slot = world.Registry.GetComponent<PointLightComponent>(1, 10u);
        Assert.Equal(50f, slot[0].Radius);
    }

    [Fact]
    public void PointLight_SyncsAfterStart_Intensity()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent").Returns(10u);

        var light = new PointLight();
        light.Initialize(1, world, "light");
        
        light.TickAwakeAndStart();

        light.Intensity = 2f;
        var slot = world.Registry.GetComponent<PointLightComponent>(1, 10u);
        Assert.Equal(2f, slot[0].Intensity);
    }

    [Fact]
    public void SpotLight_SyncsAfterStart_InnerAngle()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent").Returns(10u);

        var light = new SpotLight();
        light.Initialize(1, world, "light");
        
        light.TickAwakeAndStart();

        light.InnerAngleDegrees = 15f;
        var slot = world.Registry.GetComponent<SpotLightComponent>(1, 10u);
        Assert.Equal(15f * MathF.PI / 180f, slot[0].InnerAngle, 5);
    }

    [Fact]
    public void SpotLight_SyncsAfterStart_OuterAngle()
    {
        var world = Substitute.For<IWorld>();
        world.Registry.Returns(new FakeRegistry());
        world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent").Returns(10u);

        var light = new SpotLight();
        light.Initialize(1, world, "light");
        
        light.TickAwakeAndStart();

        light.OuterAngleDegrees = 30f;
        var slot = world.Registry.GetComponent<SpotLightComponent>(1, 10u);
        Assert.Equal(30f * MathF.PI / 180f, slot[0].OuterAngle, 5);
    }
}
