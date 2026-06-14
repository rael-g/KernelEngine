using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class LightContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public LightContributor(IEcsAdapter ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        DirectionalLightComponent dl = default;
        bool found = false;
        _ecs.Query<DirectionalLightComponent>(_components.CidOf<DirectionalLightComponent>(), (ulong _, ref DirectionalLightComponent l) =>
        {
            if (!found) { dl = l; found = true; }
        });
        if (!found) return;

        packet.SetAmbientLight(dl.Ambient.X, dl.Ambient.Y, dl.Ambient.Z);
        packet.SetDirectionalLight(new DirectionalLightData
        {
            Direction = Vector3.Normalize(dl.Direction),
            Color     = dl.Color,
            Intensity = dl.Intensity,
        });
    }
}
