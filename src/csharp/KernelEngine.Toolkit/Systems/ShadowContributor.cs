using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class ShadowResources
{
    public ShadowMapHandle? Handle;
    public uint  Resolution;
    public float FrustumSize;
    public float FarPlane;
}

internal sealed class ShadowContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;
    private readonly ShadowResources    _resources;

    public ShadowContributor(IEcsAdapter ecs, IComponentRegistry components, ShadowResources resources)
    {
        _ecs        = ecs;
        _components = components;
        _resources  = resources;
    }

    public void Contribute(IFramePacket packet)
    {
        var map = _resources.Handle;
        if (map is null) return;

        DirectionalLightComponent dl = default;
        bool foundLight = false;
        _ecs.Query<DirectionalLightComponent>(_components.CidOf<DirectionalLightComponent>(), (ulong _, ref DirectionalLightComponent l) =>
        {
            if (!foundLight) { dl = l; foundLight = true; }
        });
        if (!foundLight) return;

        var dir       = Vector3.Normalize(dl.Direction);
        var lightPos  = dir * (_resources.FarPlane * 0.5f);
        var lightView = Matrix4x4.CreateLookAt(lightPos, Vector3.Zero,
            MathF.Abs(dir.Y) > 0.99f ? Vector3.UnitZ : Vector3.UnitY);
        var lightProj = Matrix4x4.CreateOrthographic(
            _resources.FrustumSize, _resources.FrustumSize, 0.1f, _resources.FarPlane);

        packet.SetShadow(map.Value, lightView, lightProj);
        packet.SetActiveShadowMap(map.Value);

        var ecs          = _ecs;
        var transformCid = _components.CidOf<TransformComponent>();
        _ecs.Query<MeshRendererComponent>(_components.CidOf<MeshRendererComponent>(), (ulong entity, ref MeshRendererComponent mesh) =>
        {
            var world = Matrix4x4.Identity;
            if (ecs.TryGet<TransformComponent>(entity, transformCid, out var t))
                world = t.ToMatrix();
            packet.AddShadowDrawCommand(mesh.Mesh, world);
        });
    }
}
