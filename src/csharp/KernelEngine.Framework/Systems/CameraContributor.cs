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
        _ecs.Query<CameraComponent>(_components.CameraCid, (ulong e, ref CameraComponent c) =>
        {
            if (!found) { camEntity = e; cam = c; found = true; }
        });
        if (!found) return;

        // Pull world position from the camera's transform.
        var transform = TransformComponent.Identity;
        _ecs.TryGet<TransformComponent>(camEntity, _components.TransformCid, out transform);

        var size   = _window.GetSize().Value;
        var aspect = size.Height > 0 ? (float)size.Width / size.Height : 1f;

        var view = Matrix4x4.CreateLookAt(transform.Position, Vector3.Zero, Vector3.UnitY);
        var proj = Matrix4x4.CreatePerspectiveFieldOfView(
            cam.FovDeg * MathF.PI / 180f, aspect, cam.Near, cam.Far);

        packet.SetCamera(view, proj, transform.Position);
    }
}
