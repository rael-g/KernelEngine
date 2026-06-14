using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class SpotLightContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public SpotLightContributor(IEcsAdapter ecs, IComponentRegistry components)
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
