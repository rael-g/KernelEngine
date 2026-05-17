using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Render.Core;

/// <summary>
/// A wrapper for the native Mesh Rendering system.
/// The loop runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class MeshRenderSystem : ISystem
{
    private readonly ke_system_params _nativeDesc;

    public MeshRenderSystem(ke_system_params nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_params NativeDescriptor => _nativeDesc;

    public unsafe void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1]],
        Writes = []
    };
}
