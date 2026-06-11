using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Per-frame: finds the first entity with a Camera component, computes
/// view/proj from its transform + window aspect, writes them into the frame
/// packet.
/// </summary>
internal sealed class CameraContributor : IFrameContributor
{
    private readonly EcsAdapter        _ecs;
    private readonly ComponentRegistry _components;
    private readonly IWindow           _window;

    public CameraContributor(EcsAdapter ecs, ComponentRegistry components, IWindow window)
    {
        _ecs        = ecs;
        _components = components;
        _window     = window;
    }

    public void Contribute(IFramePacket packet)
    {
        // First camera entity wins. Multi-viewport / split-screen is future.
        ulong       camEntity = 0;
        CameraComponent cam   = default;
        bool        found     = false;
        _ecs.Query<CameraComponent>(_components.CidOf<CameraComponent>(), (ulong e, ref CameraComponent c) =>
        {
            if (!found) { camEntity = e; cam = c; found = true; }
        });
        if (!found) return;

        // Pull world position from the camera's transform.
        var transform = TransformComponent.Identity;
        _ecs.TryGet<TransformComponent>(camEntity, _components.CidOf<TransformComponent>(), out transform);

        var size   = _window.GetSize().Value;
        var aspect = size.Height > 0 ? (float)size.Width / size.Height : 1f;

        // Camera looks down its local -Z (matches LookAt convention). When
        // the node carries a rotation, derive forward + up from it so freelook
        // / scripted cameras work; otherwise default to looking at origin
        // along Y-up.
        Vector3 forward, up;
        if (transform.Rotation != Quaternion.Identity)
        {
            forward = Vector3.Transform(-Vector3.UnitZ, transform.Rotation);
            up      = Vector3.Transform( Vector3.UnitY, transform.Rotation);
        }
        else
        {
            forward = Vector3.Normalize(-transform.Position);  // look at origin
            if (forward.LengthSquared() < 1e-6f) forward = -Vector3.UnitZ;
            up = Vector3.UnitY;
        }
        var view = Matrix4x4.CreateLookAt(transform.Position, transform.Position + forward, up);

        Matrix4x4 proj;
        if (cam.Orthographic)
        {
            float halfH = cam.OrthographicSize;
            float halfW = halfH * aspect;
            proj = Matrix4x4.CreateOrthographic(halfW * 2f, halfH * 2f, cam.Near, cam.Far);
        }
        else
        {
            proj = Matrix4x4.CreatePerspectiveFieldOfView(
                cam.FovDeg * MathF.PI / 180f, aspect, cam.Near, cam.Far);
        }

        packet.SetCamera(view, proj, transform.Position);
    }
}
