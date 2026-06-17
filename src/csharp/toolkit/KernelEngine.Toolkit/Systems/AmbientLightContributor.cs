using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class AmbientLightContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;

    public AmbientLightContributor(IEcsRegistry ecs, IComponentRegistry components)
    {
        _ecs        = ecs;
        _components = components;
    }

    public void Contribute(IFramePacket packet)
    {
        var result = _ecs.Query<AmbientLightComponent>(_components.CidOf<AmbientLightComponent>());
        if (result.Length == 0) return;
        ref var al = ref result.Data[0];
        packet.SetAmbientLight(al.Color.X, al.Color.Y, al.Color.Z);
    }
}
