using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// A wrapper for the native Mesh Rendering system.
/// The loop runs in C++ at native speed, scheduled by the Kernel.
/// </summary>
public sealed unsafe class MeshRenderSystem : ISystem
{
    private readonly ke_system_desc _nativeDesc;

    public MeshRenderSystem(ke_system_desc nativeDesc) => _nativeDesc = nativeDesc;

    public ke_system_desc NativeDescriptor => _nativeDesc;

    private static int _dbg;
    public unsafe void Update(World world, float dt, FramePacket? packet = null)
    {
        if (packet == null) return;
        _nativeDesc.update(_nativeDesc.handle, world.Native, dt, packet.NativePointer);
        if (System.Threading.Interlocked.Increment(ref _dbg) <= 5)
            Console.Error.WriteLine($"[DBG-Mesh] draw_count={packet.NativePointer->draw_count} mesh={packet.NativePointer->draw_commands[0].mesh_handle} mat={packet.NativePointer->draw_commands[0].material_handle}");
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_nativeDesc.reads[0], _nativeDesc.reads[1]],
        Writes = []
    };
}
