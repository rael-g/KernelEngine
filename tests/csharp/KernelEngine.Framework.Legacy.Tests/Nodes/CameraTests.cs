using Xunit;
using NSubstitute;

namespace KernelEngine.Framework.Legacy.Tests;

public class CameraTests
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
    public void Properties_WorkBeforeStart_Fov()
    {
        var camera = new Camera();
        camera.Fov = 90f;
        Assert.Equal(90f, camera.Fov);
    }

    [Fact]
    public void Properties_WorkBeforeStart_Near()
    {
        var camera = new Camera();
        camera.Near = 1f;
        Assert.Equal(1f, camera.Near);
    }

    [Fact]
    public void Properties_WorkBeforeStart_Far()
    {
        var camera = new Camera();
        camera.Far = 100f;
        Assert.Equal(100f, camera.Far);
    }

    [Fact]
    public void Properties_WorkBeforeStart_OrthographicSize()
    {
        var camera = new Camera();
        camera.OrthographicSize = 10f;
        Assert.Equal(10f, camera.OrthographicSize);
    }

    [Fact]
    public void Properties_WorkBeforeStart_Orthographic()
    {
        var camera = new Camera();
        camera.Orthographic = true;
        Assert.True(camera.Orthographic);
    }

    [Fact]
    public void Start_RegistersComponent_AndSyncsValues()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.GetOrRegisterComponentId<CameraComponent>("CameraComponent").Returns(10u);
        
        var camera = new Camera();
        camera.Fov = 90f;
        camera.Initialize(1, world, "camera");

        camera.TickAwakeAndStart();

        var slot = registry.GetComponent<CameraComponent>(1, 10u);
        Assert.Equal(90f * MathF.PI / 180f, slot[0].Fov, 5);
    }

    [Fact]
    public void MakeCurrent_UpdatesActiveCamera()
    {
        var world = Substitute.For<IWorld>();
        var camera = new Camera();
        camera.Initialize(42, world, "camera");
        
        camera.MakeCurrent();

        world.Received(1).ActiveCamera = 42;
    }

    [Fact]
    public void Camera2D_SetsDefaults_Orthographic()
    {
        var camera = new Camera2D();
        Assert.True(camera.Orthographic);
    }

    [Fact]
    public void Camera2D_SetsDefaults_OrthographicSize()
    {
        var camera = new Camera2D();
        Assert.Equal(5f, camera.OrthographicSize);
    }

    [Fact]
    public void Camera2D_SetsDefaults_Near()
    {
        var camera = new Camera2D();
        Assert.Equal(0.1f, camera.Near);
    }

    [Fact]
    public void Camera2D_SetsDefaults_Far()
    {
        var camera = new Camera2D();
        Assert.Equal(100f, camera.Far);
    }

    [Fact]
    public void Camera2D_Start_SetsDefaultPosition()
    {
        var world = Substitute.For<IWorld>();
        var registry = new FakeRegistry();
        world.Registry.Returns(registry);
        world.TransformComponentId.Returns(1u);

        var camera = new Camera2D();
        camera.Initialize(1, world, "camera");

        camera.TickAwakeAndStart();

        Assert.Equal(10f, camera.LocalTransform.Position.Z);
    }
}
