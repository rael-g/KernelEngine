using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that collects mesh draw commands into the frame packet via the
/// safe <see cref="IFramePacket.AddDrawCommand"/> API.
/// </summary>
public sealed class MeshRenderSystem : ISystem
{
    private readonly uint _meshCid;
    private readonly uint _transformCid;

    public MeshRenderSystem(uint meshCid, uint transformCid)
    {
        _meshCid = meshCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld iworld, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        var world = (World)iworld;
        var registry = world.Registry;
        var meshes = registry.Query<MeshComponent>(_meshCid);

        for (int i = 0; i < meshes.Length; i++)
        {
            var mesh = meshes.Data[i];
            if (mesh.MeshHandle == MeshHandle.None) continue;

            System.Numerics.Matrix4x4 worldMatrix;
            unsafe
            {
                var tc = registry.GetComponent<TransformComponent>(meshes.Entities[i], _transformCid);
                if (tc == null) continue;
                worldMatrix = tc->WorldMatrix;
            }

            packet.AddDrawCommand(mesh.MeshHandle, mesh.MaterialHandle, worldMatrix);
        }
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_meshCid, _transformCid],
        Writes = []
    };
}
