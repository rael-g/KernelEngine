using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Holder for the shadow map handle and projection parameters. Populated by
/// <see cref="ShadowModule"/> at OnLoad once the GPU resource is created on
/// the render worker; the <see cref="ShadowContributor"/> reads from it each
/// frame and stays a no-op while the handle is still null.
/// </summary>
internal sealed class ShadowResources
{
    public ShadowMapHandle? Handle;
    public uint  Resolution;
    public float FrustumSize;
    public float FarPlane;
}

/// <summary>
/// Per-frame: when a shadow map exists and a directional light is in the
/// scene, builds an orthographic light view/projection facing the light's
/// direction, writes it into the packet, then emits one shadow draw command
/// per <see cref="MeshRendererComponent"/>.
/// </summary>
internal sealed class ShadowContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;
    private readonly ShadowResources   _resources;

    public ShadowContributor(EcsAdapter ecs, ComponentRegistry components, ShadowResources resources)
    {
        _ecs        = ecs;
        _components = components;
        _resources  = resources;
    }

    public void Contribute(IFramePacket packet)
    {
        var map = _resources.Handle;
        if (map is null) return;

        // First directional light wins; same single-light rule as LightContributor.
        DirectionalLightComponent dl = default;
        bool foundLight = false;
        _ecs.Query<DirectionalLightComponent>(_components.DirectionalLightCid, (ulong _, ref DirectionalLightComponent l) =>
        {
            if (!foundLight) { dl = l; foundLight = true; }
        });
        if (!foundLight) return;

        // Light orbits a fictitious camera at the origin. Distance picks a
        // point along -direction at a sensible offset; orthographic projection
        // covers the scene with a square frustum of side FrustumSize.
        var dir      = Vector3.Normalize(dl.Direction);
        var lightPos = dir * (_resources.FarPlane * 0.5f);
        var lightView = Matrix4x4.CreateLookAt(lightPos, Vector3.Zero,
            MathF.Abs(dir.Y) > 0.99f ? Vector3.UnitZ : Vector3.UnitY);
        var lightProj = Matrix4x4.CreateOrthographic(
            _resources.FrustumSize, _resources.FrustumSize,
            0.1f, _resources.FarPlane);

        packet.SetShadow(map.Value, lightView, lightProj);
        packet.SetActiveShadowMap(map.Value);

        // Emit shadow draw commands for every renderable mesh.
        var ecs          = _ecs;
        var transformCid = _components.TransformCid;
        _ecs.Query<MeshRendererComponent>(_components.MeshRendererCid, (ulong entity, ref MeshRendererComponent mesh) =>
        {
            var world = Matrix4x4.Identity;
            if (ecs.TryGet<TransformComponent>(entity, transformCid, out var t))
                world = t.ToMatrix();
            packet.AddShadowDrawCommand(mesh.Mesh, world);
        });
    }
}
