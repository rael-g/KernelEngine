using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class PointLightContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public PointLightContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var transformCid = _components.CidOf<TransformComponent>();
        var (entities, data) = _ecs.Query<PointLightComponent>(_components.CidOf<PointLightComponent>());
        for (int i = 0; i < entities.Length; i++)
        {
            ref var pl = ref data[i];
            var position = Vector3.Zero;
            var tsp = _ecs.GetComponent<TransformComponent>(entities[i], transformCid);
            if (!tsp.IsEmpty) position = tsp[0].Position;

            packet.AddPointLight(new PointLightData
            {
                Position  = position,
                Radius    = pl.Radius,
                Color     = pl.Color,
                Intensity = pl.Intensity,
            });
        }
    }
}
