using KernelEngine.Render;
using KernelEngine.Input;


namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Pure-managed render system that publishes the active skybox cubemap into the frame packet
/// via the safe <see cref="IFramePacket.SetSkybox"/> API.
/// </summary>
public sealed class SkyboxRenderSystem : ISystem
{
    private readonly uint _skyboxCid;

    public SkyboxRenderSystem(uint skyboxCid)
    {
        _skyboxCid = skyboxCid;
    }

    public void Update(IWorld world, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        var registry = world.Registry;

        var skyboxes = registry.Query<SkyboxComponent>(_skyboxCid);
        if (skyboxes.Length == 0) return;

        var sky = skyboxes.Data[0];
        if (!sky.CubemapHandle.IsValid) return;

        packet.SetSkybox(sky.CubemapHandle);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_skyboxCid],
        Writes = []
    };
}
