using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries the ECS for the first <see cref="DirectionalLightComponent"/>
/// and writes its direction/color/intensity + ambient into the packet.
/// </summary>
internal sealed class LightContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public LightContributor(EcsAdapter ecs, ComponentRegistry components)
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
