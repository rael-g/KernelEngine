using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries the first <see cref="AmbientLightComponent"/> and writes
/// its color into the packet. Registered before <see cref="LightContributor"/>
/// so a directional light's <c>Ambient</c> field (when present) overrides this
/// scene-wide value — the two systems are intentionally additive in that order.
/// </summary>
internal sealed class AmbientLightContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public AmbientLightContributor(EcsAdapter ecs, ComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        AmbientLightComponent al = default;
        bool found = false;
        _ecs.Query<AmbientLightComponent>(_components.AmbientLightCid, (ulong _, ref AmbientLightComponent a) =>
        {
            if (!found) { al = a; found = true; }
        });
        if (!found) return;

        packet.SetAmbientLight(al.Color.X, al.Color.Y, al.Color.Z);
    }
}
