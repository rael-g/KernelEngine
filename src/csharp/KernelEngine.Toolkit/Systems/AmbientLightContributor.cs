using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class AmbientLightContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public AmbientLightContributor(IEcsAdapter ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        AmbientLightComponent al = default;
        bool found = false;
        _ecs.Query<AmbientLightComponent>(_components.CidOf<AmbientLightComponent>(), (ulong _, ref AmbientLightComponent a) =>
        {
            if (!found) { al = a; found = true; }
        });
        if (!found) return;
        packet.SetAmbientLight(al.Color.X, al.Color.Y, al.Color.Z);
    }
}
