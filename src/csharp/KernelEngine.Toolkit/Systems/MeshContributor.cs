using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class MeshContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;
    // CID for the full 104-byte ke_transform_component (includes WorldMatrix).
    // Registered idempotently at construction time; the C scene_tree registers
    // "transform" as 104 bytes before any C# code runs, so this call returns
    // the existing CID without resizing the ECS slot.
    private readonly uint _nativeTransformCid;

    public MeshContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
        _nativeTransformCid = ecs.RegisterComponent<KernelEngine.Kernel.TransformComponent>("transform");
    }

    public void Contribute(IFramePacket packet)
    {
        var (entities, data) = _ecs.Query<MeshRendererComponent>(_components.CidOf<MeshRendererComponent>());
        for (int i = 0; i < entities.Length; i++)
        {
            ref var mesh = ref data[i];
            var world = Matrix4x4.Identity;
            var tsp = _ecs.GetComponent<KernelEngine.Kernel.TransformComponent>(entities[i], _nativeTransformCid);
            if (!tsp.IsEmpty) world = tsp[0].WorldMatrix;
            packet.AddDrawCommand(mesh.Mesh, mesh.Material, world);
        }
    }
}
