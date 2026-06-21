using System.Numerics;
using KernelEngine.Framework.Legacy;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class SceneNodeTests
{
    [Fact]
    public void DirectionalLight_InitialProperties_AreCorrect()
    {
        var light = new DirectionalLight {
            Direction = new Vector3(0, -1, 0),
            Color = new Vector3(1, 0, 0),
            Intensity = 2.0f
        };

        Assert.Equal(new Vector3(0, -1, 0), light.Direction);
        Assert.Equal(new Vector3(1, 0, 0), light.Color);
        Assert.Equal(2.0f, light.Intensity);
    }

    [Fact]
    public void DirectionalLight_SyncsToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new DirectionalLight { Direction = new Vector3(0, -1, 0) };
        tree.AddNode(light, "Sun");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<LightComponent>(light.Entity, world.GetOrRegisterComponentId<LightComponent>("LightComponent"));
        Assert.Equal(-1, compSpan[0].DirY);
    }

    [Fact]
    public void DirectionalLight_SyncsIntensityToEcs_OnUpdate()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new DirectionalLight();
        tree.AddNode(light, "Sun");
        tree.TickAwakeAndStart();

        light.Intensity = 5.0f;
        
        var compSpan = world.Registry.GetComponent<LightComponent>(light.Entity, world.GetOrRegisterComponentId<LightComponent>("LightComponent"));
        Assert.Equal(5.0f, compSpan[0].Intensity);
    }

    [Fact]
    public void DirectionalLight_SyncsDirectionToEcs_OnUpdate()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new DirectionalLight();
        tree.AddNode(light, "Sun");
        tree.TickAwakeAndStart();

        light.Direction = Vector3.UnitX;
        
        var compSpan = world.Registry.GetComponent<LightComponent>(light.Entity, world.GetOrRegisterComponentId<LightComponent>("LightComponent"));
        Assert.Equal(1.0f, compSpan[0].DirX);
    }

    [Fact]
    public void DirectionalLight_SyncsColorToEcs_OnUpdate()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new DirectionalLight();
        tree.AddNode(light, "Sun");
        tree.TickAwakeAndStart();

        light.Color = Vector3.UnitY;
        
        var compSpan = world.Registry.GetComponent<LightComponent>(light.Entity, world.GetOrRegisterComponentId<LightComponent>("LightComponent"));
        Assert.Equal(1.0f, compSpan[0].G);
    }

    [Fact]
    public void PointLight_InitialProperties_AreCorrect()
    {
        var light = new PointLight {
            Radius = 50f,
            Color = new Vector3(0, 1, 0),
            Intensity = 0.5f
        };

        Assert.Equal(50f, light.Radius);
        Assert.Equal(new Vector3(0, 1, 0), light.Color);
        Assert.Equal(0.5f, light.Intensity);
    }

    [Fact]
    public void PointLight_SyncsToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new PointLight { Radius = 50f };
        tree.AddNode(light, "Point");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<PointLightComponent>(light.Entity, world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent"));
        Assert.Equal(50f, compSpan[0].Radius);
    }

    [Fact]
    public void PointLight_SyncsRadiusToEcs_OnUpdate()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new PointLight();
        tree.AddNode(light, "Point");
        tree.TickAwakeAndStart();

        light.Radius = 100f;
        
        var compSpan = world.Registry.GetComponent<PointLightComponent>(light.Entity, world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent"));
        Assert.Equal(100f, compSpan[0].Radius);
    }

    [Fact]
    public void PointLight_SyncsIntensityToEcs_OnUpdate()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new PointLight();
        tree.AddNode(light, "Point");
        tree.TickAwakeAndStart();

        light.Intensity = 10f;
        
        var compSpan = world.Registry.GetComponent<PointLightComponent>(light.Entity, world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent"));
        Assert.Equal(10f, compSpan[0].Intensity);
    }

    [Fact]
    public void SpotLight_InitialProperties_AreCorrect()
    {
        var light = new SpotLight {
            Range = 20f,
            InnerAngleDegrees = 10f,
            OuterAngleDegrees = 45f,
            Color = new Vector3(0, 0, 1),
            Direction = Vector3.UnitZ,
            Intensity = 7f
        };

        Assert.Equal(20f, light.Range);
        Assert.Equal(10f, light.InnerAngleDegrees);
        Assert.Equal(45f, light.OuterAngleDegrees);
        Assert.Equal(new Vector3(0, 0, 1), light.Color);
        Assert.Equal(Vector3.UnitZ, light.Direction);
        Assert.Equal(7f, light.Intensity);
    }

    [Fact]
    public void SpotLight_SyncsToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new SpotLight { Range = 20f };
        tree.AddNode(light, "Spot");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<SpotLightComponent>(light.Entity, world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent"));
        Assert.Equal(20f, compSpan[0].Range);
    }

    [Fact]
    public void SpotLight_SyncsAnglesToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var light = new SpotLight { InnerAngleDegrees = 10f, OuterAngleDegrees = 45f };
        tree.AddNode(light, "Spot");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<SpotLightComponent>(light.Entity, world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent"));
        Assert.Equal(10f * MathF.PI / 180f, compSpan[0].InnerAngle, 0.001f);
        Assert.Equal(45f * MathF.PI / 180f, compSpan[0].OuterAngle, 0.001f);
    }

    [Fact]
    public void Camera_SyncsToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var camera = new Camera { Fov = 90f };
        tree.AddNode(camera, "MainCam");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<CameraComponent>(camera.Entity, world.GetOrRegisterComponentId<CameraComponent>("CameraComponent"));
        Assert.Equal(90f * MathF.PI / 180f, compSpan[0].Fov, 0.001f);
    }

    [Fact]
    public void Camera_SetsActiveCamera_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var camera = new Camera();
        tree.AddNode(camera, "MainCam");
        tree.TickAwakeAndStart();

        Assert.Equal(camera.Entity, world.ActiveCamera);
    }

    [Fact]
    public void Skybox_SyncsToEcs_OnStart()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);
        var skybox = new Skybox { CubemapHandle = new TextureHandle(99) };
        tree.AddNode(skybox, "Sky");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<SkyboxComponent>(skybox.Entity, world.GetOrRegisterComponentId<SkyboxComponent>("Skybox"));
        Assert.Equal(99u, compSpan[0].CubemapHandle.Value);
    }
}
