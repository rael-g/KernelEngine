using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class SkyboxContributor : IFrameContributor
{
    private readonly IEcsAdapter        _ecs;
    private readonly IComponentRegistry _components;

    public SkyboxContributor(IEcsAdapter ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        SkyboxComponent sb = default;
        bool found = false;
        _ecs.Query<SkyboxComponent>(_components.CidOf<SkyboxComponent>(), (ulong _, ref SkyboxComponent s) =>
        {
            if (!found) { sb = s; found = true; }
        });
        if (!found) return;
        packet.SetSkybox(sb.CubemapHandle);
    }
}
