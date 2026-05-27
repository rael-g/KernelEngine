using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Framework.Tests;

[Collection("KernelRegistry")]
public class SceneNodeTests
{
    [Fact]
    public void DirectionalLight_SyncsPropertiesToEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var light = new DirectionalLight {
            Direction = new Vector3(0, -1, 0),
            Color = new Vector3(1, 0, 0),
            Intensity = 2.0f
        };

        // Before Start
        Assert.Equal(new Vector3(0, -1, 0), light.Direction);
        Assert.Equal(new Vector3(1, 0, 0), light.Color);
        Assert.Equal(2.0f, light.Intensity);

        tree.AddNode(light, "Sun");
        tree.TickAwakeAndStart();

        // After Start
        var compSpan = world.Registry.GetComponent<LightComponent>(light.Entity, world.GetOrRegisterComponentId<LightComponent>("LightComponent"));
        Assert.False(compSpan.IsEmpty);
        Assert.Equal(0, compSpan[0].DirX);
        Assert.Equal(-1, compSpan[0].DirY);
        Assert.Equal(1, compSpan[0].R);
        Assert.Equal(2.0f, compSpan[0].Intensity);

        // Test property update after Start
        light.Intensity = 5.0f;
        Assert.Equal(5.0f, compSpan[0].Intensity);
        Assert.Equal(5.0f, light.Intensity);
        
        light.Direction = Vector3.UnitX;
        Assert.Equal(1.0f, compSpan[0].DirX);
        Assert.Equal(Vector3.UnitX, light.Direction);

        light.Color = Vector3.UnitY;
        Assert.Equal(1.0f, compSpan[0].G);
        Assert.Equal(Vector3.UnitY, light.Color);
    }

    [Fact]
    public void PointLight_SyncsPropertiesToEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var light = new PointLight {
            Radius = 50f,
            Color = new Vector3(0, 1, 0),
            Intensity = 0.5f
        };

        // Before Start
        Assert.Equal(50f, light.Radius);
        Assert.Equal(new Vector3(0, 1, 0), light.Color);
        Assert.Equal(0.5f, light.Intensity);

        tree.AddNode(light, "Point");
        tree.TickAwakeAndStart();

        // After Start
        var compSpan = world.Registry.GetComponent<PointLightComponent>(light.Entity, world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent"));
        Assert.False(compSpan.IsEmpty);
        Assert.Equal(50f, compSpan[0].Radius);
        Assert.Equal(1, compSpan[0].G);
        Assert.Equal(0.5f, compSpan[0].Intensity);

        light.Radius = 100f;
        Assert.Equal(100f, compSpan[0].Radius);
        Assert.Equal(100f, light.Radius);
        
        light.Intensity = 10f;
        Assert.Equal(10f, compSpan[0].Intensity);
        Assert.Equal(10f, light.Intensity);

        light.Color = Vector3.One;
        Assert.Equal(1f, compSpan[0].R);
        Assert.Equal(Vector3.One, light.Color);
    }

    [Fact]
    public void SpotLight_SyncsPropertiesToEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var light = new SpotLight {
            Range = 20f,
            InnerAngleDegrees = 10f,
            OuterAngleDegrees = 45f,
            Color = new Vector3(0, 0, 1),
            Direction = Vector3.UnitZ,
            Intensity = 7f
        };

        // Before Start
        Assert.Equal(20f, light.Range);
        Assert.Equal(10f, light.InnerAngleDegrees);
        Assert.Equal(45f, light.OuterAngleDegrees);
        Assert.Equal(new Vector3(0, 0, 1), light.Color);
        Assert.Equal(Vector3.UnitZ, light.Direction);
        Assert.Equal(7f, light.Intensity);

        tree.AddNode(light, "Spot");
        tree.TickAwakeAndStart();

        // After Start
        var compSpan = world.Registry.GetComponent<SpotLightComponent>(light.Entity, world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent"));
        Assert.False(compSpan.IsEmpty);
        Assert.Equal(20f, compSpan[0].Range);
        Assert.Equal(10f * MathF.PI / 180f, compSpan[0].InnerAngle, 0.001f);
        Assert.Equal(45f * MathF.PI / 180f, compSpan[0].OuterAngle, 0.001f);
        Assert.Equal(1, compSpan[0].B);
        Assert.Equal(1, compSpan[0].DirZ);
        Assert.Equal(7f, compSpan[0].Intensity);

        light.Range = 30f;
        Assert.Equal(30f, compSpan[0].Range);
        Assert.Equal(30f, light.Range);

        light.InnerAngleDegrees = 20f;
        Assert.Equal(20f * MathF.PI / 180f, compSpan[0].InnerAngle, 0.001f);
        Assert.Equal(20f, light.InnerAngleDegrees);

        light.OuterAngleDegrees = 60f;
        Assert.Equal(60f * MathF.PI / 180f, compSpan[0].OuterAngle, 0.001f);
        Assert.Equal(60f, light.OuterAngleDegrees);

        light.Intensity = 100f;
        Assert.Equal(100f, compSpan[0].Intensity);
        Assert.Equal(100f, light.Intensity);

        light.Color = Vector3.Zero;
        Assert.Equal(0, compSpan[0].R);
        Assert.Equal(Vector3.Zero, light.Color);

        light.Direction = Vector3.UnitY;
        Assert.Equal(1f, compSpan[0].DirY);
        Assert.Equal(Vector3.UnitY, light.Direction);
    }

    [Fact]
    public void Camera_SyncsPropertiesToEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var camera = new Camera {
            Fov = 90f,
            Near = 1f,
            Far = 500f,
            Orthographic = true
        };

        tree.AddNode(camera, "MainCam");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<CameraComponent>(camera.Entity, world.GetOrRegisterComponentId<CameraComponent>("CameraComponent"));
        Assert.False(compSpan.IsEmpty);
        Assert.Equal(90f * MathF.PI / 180f, compSpan[0].Fov, 0.001f);
        Assert.Equal(1f, compSpan[0].Near);
        Assert.Equal(1, compSpan[0].Orthographic);
        
        Assert.Equal(camera.Entity, world.ActiveCamera);
    }

    [Fact]
    public void Skybox_SyncsPropertiesToEcs()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var tree = new Tree(world);

        var skybox = new Skybox {
            CubemapHandle = new TextureHandle(99)
        };

        tree.AddNode(skybox, "Sky");
        tree.TickAwakeAndStart();

        var compSpan = world.Registry.GetComponent<SkyboxComponent>(skybox.Entity, world.GetOrRegisterComponentId<SkyboxComponent>("Skybox"));
        Assert.False(compSpan.IsEmpty);
        Assert.Equal(99u, compSpan[0].CubemapHandle.Value);
    }
}
