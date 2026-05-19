using KernelEngine.Framework.Internal;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed render system that extracts camera state from the ECS and publishes it into the
/// frame packet via the safe <see cref="IFramePacket.SetCamera"/> API. Math is column-major
/// (matches <c>ke_mat4</c>, right-handed, Vulkan depth [0,1]).
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

    public void Update(IWorld iworld, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        var world = (World)iworld;
        var registry = world.Registry;

        var cameras = registry.Query<CameraComponent>(_cameraCid);
        if (cameras.Length == 0) return;

        // ECS storage read requires a pointer; keep the unsafe scope minimal.
        TransformComponent transform;
        unsafe
        {
            var p = registry.GetComponentRaw<TransformComponent>(cameras.Entities[0], _transformCid);
            if (p == null) return;
            transform = *p;
        }

        var cam = cameras.Data[0];
        var view = Mat4.InvertTrs(transform.WorldMatrix);
        var proj = cam.Orthographic != 0
            ? Mat4.Ortho(-Aspect * 10f, Aspect * 10f, -10f, 10f, cam.Near, cam.Far)
            : Mat4.Perspective(cam.Fov, Aspect, cam.Near, cam.Far);

        packet.SetCamera(view, proj, transform.Position);
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_cameraCid, _transformCid],
        Writes = []
    };
}
