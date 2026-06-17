using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

internal sealed class CameraContributor : IFrameContributor
{
    private readonly IEcsRegistry       _ecs;
    private readonly IComponentRegistry _components;
    private readonly IWindow            _window;

    public CameraContributor(IEcsRegistry ecs, IComponentRegistry components, IWindow window)
    {
        _ecs        = ecs;
        _components = components;
        _window     = window;
    }

    public void Contribute(IFramePacket packet)
    {
        var camResult = _ecs.Query<CameraComponent>(_components.CidOf<CameraComponent>());
        if (camResult.Length == 0) return;
        var camEntity = camResult.Entities[0];
        ref var cam   = ref camResult.Data[0];

        var transform = TransformComponent.Identity;
        var tsp = _ecs.GetComponent<TransformComponent>(camEntity, _components.CidOf<TransformComponent>());
        if (!tsp.IsEmpty) transform = tsp[0];

        var size   = _window.GetSize().Value;
        var aspect = size.Height > 0 ? (float)size.Width / size.Height : 1f;

        Vector3 forward, up;
        if (transform.Rotation != Quaternion.Identity)
        {
            forward = Vector3.Transform(-Vector3.UnitZ, transform.Rotation);
            up      = Vector3.Transform( Vector3.UnitY, transform.Rotation);
        }
        else
        {
            forward = Vector3.Normalize(-transform.Position);
            if (forward.LengthSquared() < 1e-6f) forward = -Vector3.UnitZ;
            up = Vector3.UnitY;
        }
        var view = Matrix4x4.CreateLookAt(transform.Position, transform.Position + forward, up);

        Matrix4x4 proj;
        if (cam.Orthographic != 0)
        {
            float halfH = cam.OrthographicSize;
            float halfW = halfH * aspect;
            proj = Matrix4x4.CreateOrthographic(halfW * 2f, halfH * 2f, cam.NearPlane, cam.FarPlane);
        }
        else
        {
            proj = Matrix4x4.CreatePerspectiveFieldOfView(
                cam.Fov * MathF.PI / 180f, aspect, cam.NearPlane, cam.FarPlane);
        }

        packet.SetCamera(view, proj, transform.Position);
    }
}
