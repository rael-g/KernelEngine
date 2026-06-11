using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Configures the per-frame camera (view + projection + world-space position)
/// from a fixed setup. Contributes to the frame packet so the renderer's main
/// pass uses these matrices.
/// </summary>
public sealed class CameraModule : IRuntimeModule, IFrameContributor
{
    public Vector3 Position { get; init; } = new(0, 0, 3);
    public Vector3 Target   { get; init; } = Vector3.Zero;
    public Vector3 Up       { get; init; } = Vector3.UnitY;
    public float   FovDeg   { get; init; } = 60f;
    public float   Near     { get; init; } = 0.1f;
    public float   Far      { get; init; } = 1000f;

    public string Name => "Camera";

    private IWindow? _window;

    public void Configure(IServiceCollection services) => services.AddSingleton<IFrameContributor>(this);

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        _window = services.GetRequiredService<IWindow>();
    }

    public void Contribute(IFramePacket packet)
    {
        if (_window == null) return;
        var size   = _window.GetSize().Value;
        var aspect = size.Height > 0 ? (float)size.Width / size.Height : 1f;

        var view = Matrix4x4.CreateLookAt(Position, Target, Up);
        var proj = Matrix4x4.CreatePerspectiveFieldOfView(
            FovDeg * MathF.PI / 180f, aspect, Near, Far);

        packet.SetCamera(view, proj, Position);
    }
}
