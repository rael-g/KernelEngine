using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries every entity with a <see cref="SpotLightComponent"/>,
/// reads its transform for world position, and appends one
/// <see cref="IFramePacket.AddSpotLight"/> per match. Direction comes from the
/// component (light cones don't follow the entity's rotation automatically;
/// scripted nodes update Direction explicitly when needed).
/// </summary>
internal sealed class SpotLightContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public SpotLightContributor(EcsAdapter ecs, ComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var ecs          = _ecs;
        var transformCid = _components.CidOf<TransformComponent>();

        _ecs.Query<SpotLightComponent>(_components.CidOf<SpotLightComponent>(), (ulong entity, ref SpotLightComponent sl) =>
        {
            var position = Vector3.Zero;
            if (ecs.TryGet<TransformComponent>(entity, transformCid, out var t))
                position = t.Position;

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
        });
    }
}
