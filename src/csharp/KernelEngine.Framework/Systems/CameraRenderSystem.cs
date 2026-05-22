using System.Numerics;
using KernelEngine.Framework.Internal;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that extracts camera state from the ECS and publishes it into the
/// frame packet via the safe <see cref="IFramePacket.SetCamera"/> API. The view matrix is the
/// inverse of the camera's world transform (System.Numerics); the projection is built in the active
/// backend's NDC convention by <see cref="Projection"/>.
/// </summary>
public sealed class CameraRenderSystem : ISystem
{
    private const float Aspect = 1.77f; // 16:9 — TODO: query from window once exposed

    private readonly uint _cameraCid;
    private readonly uint _transformCid;

    public CameraRenderSystem(uint cameraCid, uint transformCid)
    {
        _cameraCid = cameraCid;
        _transformCid = transformCid;
    }

    public void Update(IWorld world, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        var registry = world.Registry;

        var cameras = registry.Query<CameraComponent>(_cameraCid);
        if (cameras.Length == 0) return;

        TransformComponent transform;
        { var slot = registry.GetComponent<TransformComponent>(cameras.Entities[0], _transformCid); if (slot.IsEmpty) return; transform = slot[0]; }

        var cam = cameras.Data[0];
        // WorldMatrix carries column-major ke_mat4 bytes; inverting it (treated as the .NET-side
        // transpose) yields the column-major view directly — the double transpose cancels.
        var view = Matrix4x4.Invert(transform.WorldMatrix, out var inv) ? inv : Matrix4x4.Identity;
        var proj = cam.Orthographic != 0
            ? ViewProjection.Ortho(-Aspect * 10f, Aspect * 10f, -10f, 10f, cam.Near, cam.Far)
            : ViewProjection.Perspective(cam.Fov, Aspect, cam.Near, cam.Far);

        packet.SetCamera(view, proj, transform.Position);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_cameraCid, _transformCid],
        Writes = []
    };
}
