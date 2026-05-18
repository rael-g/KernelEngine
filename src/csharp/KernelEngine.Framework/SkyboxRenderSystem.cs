using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;


/// <summary>
/// Pure-managed render system that publishes the active skybox cubemap into the frame packet.
/// Replaces the legacy C++ SkyboxSystem.
/// </summary>
public sealed unsafe class SkyboxRenderSystem : ISystem
{
    private readonly uint _skyboxCid;

    public SkyboxRenderSystem(uint skyboxCid)
    {
        _skyboxCid = skyboxCid;
    }

    public void Update(IWorld iworld, float dt, IFramePacket? ipacket = null, IInputReader? input = null)
    {
        if (ipacket == null) return;
        var world = (World)iworld;
        var packet = (FramePacket)ipacket;

        var registry = world.Registry;
        var skyboxes = registry.Query<SkyboxComponent>(_skyboxCid);
        if (skyboxes.Length == 0) return;

        var sky = skyboxes.Data[0];
        if (!sky.CubemapHandle.IsValid) return;

        var raw = packet.NativePointer;
        raw->skybox_handle = new ke_texture_handle { idx = sky.CubemapHandle.Value };
        raw->has_skybox = true;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_skyboxCid],
        Writes = []
    };
}
