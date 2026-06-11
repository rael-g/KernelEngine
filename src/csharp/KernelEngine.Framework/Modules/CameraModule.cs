using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Sets the renderer view + projection matrices every Update tick from a
/// configurable camera. Pinned to the render worker. First minimal port from
/// .Legacy CameraNode + CameraRenderSystem — full Camera node + multi-camera
/// support lands as later examples need it.
/// </summary>
public sealed class CameraModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    public Vector3 Position { get; init; } = new(0, 0, 3);
    public Vector3 Target   { get; init; } = Vector3.Zero;
    public Vector3 Up       { get; init; } = Vector3.UnitY;
    public float   FovDeg   { get; init; } = 60f;
    public float   Near     { get; init; } = 0.1f;
    public float   Far      { get; init; } = 1000f;

    public string Name => "Camera";

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window   = services.GetRequiredService<IWindow>();
        var renderer = services.GetRequiredService<IRenderer>();

        runtime.RegisterSystem("Camera.SetView", RuntimePhase.Update, (_, _) =>
        {
            var size   = window.GetSize().Value;
            var aspect = size.Height > 0 ? (float)size.Width / size.Height : 1f;

            var view = Matrix4x4.CreateLookAt(Position, Target, Up);
            var proj = Matrix4x4.CreatePerspectiveFieldOfView(
                FovDeg * MathF.PI / 180f, aspect, Near, Far);

            renderer.SetViewTransform(view, proj);
        }, pinnedThread: RenderWorker);
    }
}
