using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class LightContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public LightContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var result = _ecs.Query<DirectionalLightComponent>(_components.CidOf<DirectionalLightComponent>());
        if (result.Length == 0) return;
        ref var dl = ref result.Data[0];

        packet.SetAmbientLight(dl.Ambient.X, dl.Ambient.Y, dl.Ambient.Z);
        packet.SetDirectionalLight(new DirectionalLightData
        {
            Direction = Vector3.Normalize(dl.Direction),
            Color     = dl.Color,
            Intensity = dl.Intensity,
        });
    }
}
