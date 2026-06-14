using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class MeshContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public MeshContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var transformCid = _components.CidOf<TransformComponent>();
        var (entities, data) = _ecs.Query<MeshRendererComponent>(_components.CidOf<MeshRendererComponent>());
        for (int i = 0; i < entities.Length; i++)
        {
            ref var mesh = ref data[i];
            var world = Matrix4x4.Identity;
            var tsp = _ecs.GetComponent<TransformComponent>(entities[i], transformCid);
            if (!tsp.IsEmpty) world = tsp[0].ToMatrix();
            packet.AddDrawCommand(mesh.Mesh, mesh.Material, world);
        }
    }
}
