using System.Numerics;
using KernelEngine.Framework.Legacy;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

[Collection("KernelRegistry")]
public class RenderSystemTests
{
    [Fact]
    public void LightRenderSystem_PublishesLightsToPacket()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);

        var dirCid   = world.GetOrRegisterComponentId<LightComponent>("LightComponent");
        var pointCid = world.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent");
        var spotCid  = world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent");

        var system = new LightRenderSystem(dirCid, pointCid, spotCid, world.TransformComponentId);
        var mockPacket = Substitute.For<IFramePacket>();

        // 1. Directional
        var ent1 = world.Registry.CreateEntity();
        var l1 = world.Registry.AddComponent<LightComponent>(ent1, dirCid);
        Assert.False(l1.IsEmpty, $"Failed to add LightComponent {dirCid} to entity {ent1}");
        l1[0] = new LightComponent { DirY = -1, R = 1, Intensity = 2 };

        // 2. Point
        var ent2 = world.Registry.CreateEntity();
        var l2 = world.Registry.AddComponent<PointLightComponent>(ent2, pointCid);
        Assert.False(l2.IsEmpty, $"Failed to add PointLightComponent {pointCid} to entity {ent2}");
        l2[0] = new PointLightComponent { Radius = 10, G = 1, Intensity = 1 };
        var t2 = world.Registry.AddComponent<TransformComponent>(ent2, world.TransformComponentId);
        t2[0] = new TransformComponent { Position = new Vector3(5, 5, 5) };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).SetDirectionalLight(Arg.Is<DirectionalLightData>(d => d.Intensity == 2 && d.Direction.Y == -1));
        mockPacket.Received(1).AddPointLight(Arg.Is<PointLightData>(d => d.Radius == 10 && d.Position.X == 5));
    }

    [Fact]
    public void LightRenderSystem_PublishesSpotLights()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var spotCid = world.GetOrRegisterComponentId<SpotLightComponent>("SpotLightComponent");

        var system = new LightRenderSystem(0, 0, spotCid, world.TransformComponentId);
        var mockPacket = Substitute.For<IFramePacket>();

        var ent = world.Registry.CreateEntity();
        var l = world.Registry.AddComponent<SpotLightComponent>(ent, spotCid);
        l[0] = new SpotLightComponent { Range = 50, Intensity = 3, InnerAngle = 0.1f, OuterAngle = 0.5f };
        var t = world.Registry.AddComponent<TransformComponent>(ent, world.TransformComponentId);
        t[0] = new TransformComponent { Position = new Vector3(1, 1, 1), WorldMatrix = Matrix4x4.Identity };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).AddSpotLight(Arg.Is<SpotLightData>(d => d.Range == 50 && d.Intensity == 3));
    }

    [Fact]
    public void SkyboxRenderSystem_PublishesSkyboxToPacket()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var skyCid = world.GetOrRegisterComponentId<SkyboxComponent>("Skybox");

        var system = new SkyboxRenderSystem(skyCid);
        var mockPacket = Substitute.For<IFramePacket>();

        var ent = world.Registry.CreateEntity();
        var s = world.Registry.AddComponent<SkyboxComponent>(ent, skyCid);
        s[0] = new SkyboxComponent { CubemapHandle = new TextureHandle(99) };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).SetSkybox(Arg.Is<TextureHandle>(h => h.Value == 99));
    }

    [Fact]
    public void MeshRenderSystem_PublishesDrawCommands()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var meshCid = world.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");

        var system = new MeshRenderSystem(meshCid, world.TransformComponentId);
        var mockPacket = Substitute.For<IFramePacket>();

        var ent = world.Registry.CreateEntity();
        var m = world.Registry.AddComponent<MeshComponent>(ent, meshCid);
        m[0] = new MeshComponent { MeshHandle = new MeshHandle(10), MaterialHandle = new MaterialHandle(20) };
        var t = world.Registry.AddComponent<TransformComponent>(ent, world.TransformComponentId);
        t[0] = new TransformComponent { WorldMatrix = Matrix4x4.CreateTranslation(1, 2, 3) };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).AddDrawCommand(
            Arg.Is<MeshHandle>(h => h.Value == 10),
            Arg.Is<MaterialHandle>(h => h.Value == 20),
            Arg.Is<Matrix4x4>(m => m.M41 == 1));
    }

    [Fact]
    public void CameraRenderSystem_PublishesCameraState()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var camCid = world.GetOrRegisterComponentId<CameraComponent>("CameraComponent");

        var system = new CameraRenderSystem(camCid, world.TransformComponentId);
        var mockPacket = Substitute.For<IFramePacket>();

        var ent = world.Registry.CreateEntity();
        var c = world.Registry.AddComponent<CameraComponent>(ent, camCid);
        c[0] = new CameraComponent { Fov = 1.0f, Near = 0.1f, Far = 100f, Orthographic = 0 };
        var t = world.Registry.AddComponent<TransformComponent>(ent, world.TransformComponentId);
        t[0] = new TransformComponent { Position = new Vector3(0, 0, 10), WorldMatrix = Matrix4x4.CreateTranslation(0, 0, 10) };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).SetCamera(
            Arg.Any<Matrix4x4>(),
            Arg.Any<Matrix4x4>(),
            Arg.Is<Vector3>(v => v.Z == 10));
    }

    [Fact]
    public void ShadowRenderSystem_PublishesShadowState()
    {
        using var allocator = new MallocAllocator();
        using var world = new World(allocator);
        var dirCid  = world.GetOrRegisterComponentId<LightComponent>("LightComponent");
        var meshCid = world.GetOrRegisterComponentId<MeshComponent>("ke_mesh_renderer");

        var system = new ShadowRenderSystem(dirCid, meshCid, world.TransformComponentId);
        system.SetShadowMap(new ShadowMapHandle(5));
        var mockPacket = Substitute.For<IFramePacket>();

        // Light
        var ent1 = world.Registry.CreateEntity();
        var l = world.Registry.AddComponent<LightComponent>(ent1, dirCid);
        l[0] = new LightComponent { DirY = -1 };

        // Caster
        var ent2 = world.Registry.CreateEntity();
        var m = world.Registry.AddComponent<MeshComponent>(ent2, meshCid);
        m[0] = new MeshComponent { MeshHandle = new MeshHandle(50) };
        var t = world.Registry.AddComponent<TransformComponent>(ent2, world.TransformComponentId);
        t[0] = new TransformComponent { WorldMatrix = Matrix4x4.Identity };

        system.Update(world, 0.16f, mockPacket);

        mockPacket.Received(1).SetShadow(Arg.Is<ShadowMapHandle>(h => h.Value == 5), Arg.Any<Matrix4x4>(), Arg.Any<Matrix4x4>());
        mockPacket.Received(1).AddShadowDrawCommand(Arg.Is<MeshHandle>(h => h.Value == 50), Arg.Any<Matrix4x4>());
    }
}
