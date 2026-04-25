using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Wrapper for the native Shadow Rendering system.
/// The shadow caster loop runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class ShadowRenderSystem : ISystem
{
    private readonly ke_system_desc _nativeDesc;

    public ShadowRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_desc NativeDescriptor => _nativeDesc;

    public void Update(World world, float dt, FramePacket? packet = null) { }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1], _nativeDesc.reads[2]],
        Writes = []
    };
}
