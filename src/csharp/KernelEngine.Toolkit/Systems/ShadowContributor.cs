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
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;
    private readonly ShadowResources    _resources;

    public ShadowContributor(IEcsRegistry ecs, IComponentRegistry components, ShadowResources resources)
    {
        _ecs        = ecs;
        _components = components;
        _resources  = resources;
    }

    public void Contribute(IFramePacket packet)
    {
        var map = _resources.Handle;
        if (map is null) return;

        var lightResult = _ecs.Query<DirectionalLightComponent>(_components.CidOf<DirectionalLightComponent>());
        if (lightResult.Length == 0) return;
        ref var dl = ref lightResult.Data[0];

        var dir       = Vector3.Normalize(dl.Direction);
        var lightPos  = dir * (_resources.FarPlane * 0.5f);
        var lightView = Matrix4x4.CreateLookAt(lightPos, Vector3.Zero,
            MathF.Abs(dir.Y) > 0.99f ? Vector3.UnitZ : Vector3.UnitY);
        var lightProj = Matrix4x4.CreateOrthographic(
            _resources.FrustumSize, _resources.FrustumSize, 0.1f, _resources.FarPlane);

        packet.SetShadow(map.Value, lightView, lightProj);
        packet.SetActiveShadowMap(map.Value);

        var transformCid = _components.CidOf<TransformComponent>();
        var (entities, data) = _ecs.Query<MeshRendererComponent>(_components.CidOf<MeshRendererComponent>());
        for (int i = 0; i < entities.Length; i++)
        {
            ref var mesh = ref data[i];
            var world = Matrix4x4.Identity;
            var tsp = _ecs.GetComponent<TransformComponent>(entities[i], transformCid);
            if (!tsp.IsEmpty) world = tsp[0].ToMatrix();
            packet.AddShadowDrawCommand(mesh.Mesh, world);
        }
    }
}
