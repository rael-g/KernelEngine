using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Wrapper for the native Skybox system.
/// The skybox recording logic runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class SkyboxRenderSystem : ISystem
{
    private readonly ke_system_desc _nativeDesc;

    public SkyboxRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_desc NativeDescriptor => _nativeDesc;

    public unsafe void Update(World world, float dt, FramePacket? packet = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0]],
        Writes = []
    };
}
