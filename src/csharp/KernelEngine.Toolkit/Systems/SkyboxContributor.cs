using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class SkyboxContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public SkyboxContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var result = _ecs.Query<SkyboxComponent>(_components.CidOf<SkyboxComponent>());
        if (result.Length == 0) return;
        packet.SetSkybox(result.Data[0].CubemapHandle);
    }
}
