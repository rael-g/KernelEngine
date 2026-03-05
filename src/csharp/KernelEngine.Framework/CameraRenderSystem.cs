using System.Numerics;
using KernelEngine;

namespace KernelEngine.Framework;

/// <summary>
/// Reads the active camera's <see cref="CameraComponent"/> and <see cref="TransformComponent"/>,
/// computes view and projection matrices, and uploads them to the renderer each frame.
/// Must run before <see cref="MeshRenderSystem"/>.
/// </summary>
public sealed unsafe class CameraRenderSystem : ISystem
{
    private readonly Renderer _renderer;
    private readonly Window _window;

    public CameraRenderSystem(Renderer renderer, Window window)
    {
        _renderer = renderer;
        _window = window;
    }

    public void Update(World world, float dt)
    {
        if (world.ActiveCamera == 0) return;

        var tc = world.Registry.GetComponent<TransformComponent>(world.ActiveCamera, world.TransformComponentId);
        if (tc == null) return;

        if (CameraNode.ComponentId == uint.MaxValue) return;
        var cc = world.Registry.GetComponent<CameraComponent>(world.ActiveCamera, CameraNode.ComponentId);
        if (cc == null) return;

        // View matrix = inverse of the camera's world transform
        Matrix4x4.Invert(tc->WorldMatrix, out var view);

        var (w, h) = _window.GetSize();
        float aspect = h > 0 ? (float)w / h : 1f;

        Matrix4x4 proj = cc->Orthographic != 0
            ? Matrix4x4.CreateOrthographic(aspect * 10f, 10f, cc->Near, cc->Far)
            : Matrix4x4.CreatePerspectiveFieldOfView(cc->Fov * MathF.PI / 180f, aspect, cc->Near, cc->Far);

        _renderer.SetViewTransform(view, proj);

        // Upload camera world position for PBR specular
        _renderer.SetCameraPos(tc->WorldMatrix.M41, tc->WorldMatrix.M42, tc->WorldMatrix.M43);
    }
}
