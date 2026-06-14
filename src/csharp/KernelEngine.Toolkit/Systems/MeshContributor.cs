using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class MeshContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public MeshContributor(IEcsAdapter ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var ecs          = _ecs;
        var transformCid = _components.CidOf<TransformComponent>();

        _ecs.Query<MeshRendererComponent>(_components.CidOf<MeshRendererComponent>(), (ulong entity, ref MeshRendererComponent mesh) =>
        {
            var world = Matrix4x4.Identity;
            if (ecs.TryGet<TransformComponent>(entity, transformCid, out var t))
                world = t.ToMatrix();
            packet.AddDrawCommand(mesh.Mesh, mesh.Material, world);
        });
    }
}
