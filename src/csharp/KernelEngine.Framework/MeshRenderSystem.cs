using System.Runtime.CompilerServices;
using System.Threading;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that collects mesh draw commands into the frame packet.
/// Replaces the legacy C++ MeshSystem.
/// </summary>
public sealed unsafe class MeshRenderSystem : ISystem
{
    private readonly uint _meshCid;
    private readonly uint _transformCid;

    public MeshRenderSystem(uint meshCid, uint transformCid)
    {
        _meshCid = meshCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld iworld, float dt, IFramePacket? ipacket = null, IInputReader? input = null)
    {
        if (ipacket == null) return;
        var world = (World)iworld;
        var packet = (FramePacket)ipacket;

        var registry = world.Registry;
        var raw = packet.NativePointer;
        var meshes = registry.Query<MeshComponent>(_meshCid);

        for (int i = 0; i < meshes.Length; i++)
        {
            var mesh = meshes.Data[i];
            if (mesh.MeshHandle == MeshHandle.None) continue;

            var tc = registry.GetComponent<TransformComponent>(meshes.Entities[i], _transformCid);
            if (tc == null) continue;

            // Atomic write — mirrors the C++ behaviour even though no other system writes to draw_count.
            uint index = (uint)Interlocked.Increment(ref Unsafe.As<uint, int>(ref raw->draw_count)) - 1;
            if (index < raw->draw_capacity)
            {
                var cmd = &raw->draw_commands[index];
                cmd->mesh_handle = new ke_mesh_handle { idx = mesh.MeshHandle.Value };
                cmd->material_handle = new ke_material_handle { idx = mesh.MaterialHandle.Value };
                cmd->transform = Unsafe.As<System.Numerics.Matrix4x4, ke_mat4>(ref tc->WorldMatrix);
            }
        }
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_meshCid, _transformCid],
        Writes = []
    };
}
