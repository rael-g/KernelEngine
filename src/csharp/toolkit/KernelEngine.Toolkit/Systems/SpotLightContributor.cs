using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class SpotLightContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public SpotLightContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var transformCid = _components.CidOf<TransformComponent>();
        var (entities, data) = _ecs.Query<SpotLightComponent>(_components.CidOf<SpotLightComponent>());
        for (int i = 0; i < entities.Length; i++)
        {
            ref var sl = ref data[i];
            var position = Vector3.Zero;
            var tsp = _ecs.GetComponent<TransformComponent>(entities[i], transformCid);
            if (!tsp.IsEmpty) position = tsp[0].Position;

            packet.AddSpotLight(new SpotLightData
            {
                Position   = position,
                Range      = sl.Range,
                Direction  = Vector3.Normalize(sl.Direction),
                InnerAngle = sl.InnerAngleDeg * MathF.PI / 180f,
                OuterAngle = sl.OuterAngleDeg * MathF.PI / 180f,
                Color      = sl.Color,
                Intensity  = sl.Intensity,
            });
        }
    }
}
