using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Wrapper for the native Light Rendering system.
/// The lighting loop runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class LightRenderSystem : ISystem
{
    private readonly ke_system_desc _nativeDesc;

    public LightRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_desc NativeDescriptor => _nativeDesc;

    public unsafe void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1], _nativeDesc.reads[2], _nativeDesc.reads[3]],
        Writes = []
    };
}
