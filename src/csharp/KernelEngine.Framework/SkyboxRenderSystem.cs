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

    public void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;

        var registry = world.Registry;
        var skyboxes = registry.Query<ke_skybox_component>(_skyboxCid);
        if (skyboxes.Length == 0) return;

        var sky = skyboxes.Data[0];
        if (sky.cubemap_handle.idx == uint.MaxValue) return;

        var raw = packet.NativePointer;
        raw->skybox_handle = sky.cubemap_handle;
        raw->has_skybox = true;
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_skyboxCid],
        Writes = []
    };
}
