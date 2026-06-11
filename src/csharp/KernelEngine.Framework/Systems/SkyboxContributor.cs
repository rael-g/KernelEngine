using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: queries the ECS for the first <see cref="SkyboxComponent"/> and
/// writes its cubemap handle into the packet. Same first-entity-wins shape as
/// the directional light — multi-skybox scenes never made sense.
/// </summary>
internal sealed class SkyboxContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;

    public SkyboxContributor(EcsAdapter ecs, ComponentRegistry components)
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
