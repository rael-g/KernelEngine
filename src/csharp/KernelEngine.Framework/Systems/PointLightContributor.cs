using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries every entity with a <see cref="PointLightComponent"/>,
/// reads its transform for world position, and appends one
/// <see cref="IFramePacket.AddPointLight"/> per match. The packet's internal
/// capacity caps the count silently — extra lights past the cap are dropped.
/// </summary>
internal sealed class PointLightContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public PointLightContributor(EcsAdapter ecs, ComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var ecs          = _ecs;
        var transformCid = _components.TransformCid;

        _ecs.Query<PointLightComponent>(_components.PointLightCid, (ulong entity, ref PointLightComponent pl) =>
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
