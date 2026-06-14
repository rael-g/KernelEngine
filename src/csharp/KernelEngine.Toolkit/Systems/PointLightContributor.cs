using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class PointLightContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public PointLightContributor(IEcsAdapter ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var ecs          = _ecs;
        var transformCid = _components.CidOf<TransformComponent>();

        _ecs.Query<PointLightComponent>(_components.CidOf<PointLightComponent>(), (ulong entity, ref PointLightComponent pl) =>
        {
            var position = Vector3.Zero;
            if (ecs.TryGet<TransformComponent>(entity, transformCid, out var t))
                position = t.Position;

            packet.AddPointLight(new PointLightData
            {
                Position  = position,
                Radius    = pl.Radius,
                Color     = pl.Color,
                Intensity = pl.Intensity,
            });
        });
    }
}
