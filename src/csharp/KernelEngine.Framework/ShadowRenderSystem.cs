using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using BgfxNative = KernelEngine.Render.Bgfx.Native.NativeMethods;

namespace KernelEngine.Framework;

/// <summary>
/// Wrapper for the native Shadow Rendering system.
/// The shadow caster loop runs in C++ at native speed, scheduled by the Kernel.
/// Call <see cref="SetShadowMap"/> from ke.render after GPU initialization.
/// </summary>
public sealed unsafe class ShadowRenderSystem : ISystem
{
    private ke_system_desc _nativeDesc;

    public ShadowRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    /// <summary>
    /// Injects the pre-created shadow map handle into the native system context.
    /// Must be called from ke.render before the first frame.
    /// </summary>
    public void SetShadowMap(ShadowMapHandle handle)
    {
        fixed (ke_system_desc* desc = &_nativeDesc)
            BgfxNative.render_bgfx_shadow_system_set_map(desc, new ke_shadow_map_handle { idx = handle.Value });
    }

    public ke_system_desc NativeDescriptor => _nativeDesc;

    public unsafe void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1], _nativeDesc.reads[2]],
        Writes = []
    };
}
