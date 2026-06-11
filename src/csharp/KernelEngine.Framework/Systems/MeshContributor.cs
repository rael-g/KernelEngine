using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries every entity with a <see cref="MeshRendererComponent"/>
/// and emits one <see cref="IFramePacket.AddDrawCommand"/> per match, using
/// the entity's transform (identity when missing).
/// </summary>
internal sealed class MeshContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public MeshContributor(EcsAdapter ecs, ComponentRegistry components)
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
