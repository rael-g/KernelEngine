using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Wrapper for the native Camera system.
/// View/proj computation runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class CameraRenderSystem : ISystem
{
    private readonly ke_system_desc _nativeDesc;

    public CameraRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_desc NativeDescriptor => _nativeDesc;

    private static int _dbg;
    public unsafe void Update(World world, float dt, FramePacket? packet = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
        if (System.Threading.Interlocked.Increment(ref _dbg) <= 3)
        {
            var c = packet.NativePointer->camera;
            Console.Error.WriteLine($"[DBG-Cam] pos=({c.pos_x:F2},{c.pos_y:F2},{c.pos_z:F2}) view[14]={c.view.m[14]:F3} proj[0]={c.proj.m[0]:F3} proj[5]={c.proj.m[5]:F3} proj[10]={c.proj.m[10]:F4} proj[11]={c.proj.m[11]:F3}");
        }
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1]],
        Writes = []
    };
}
