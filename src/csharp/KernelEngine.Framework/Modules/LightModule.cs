using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Sets a directional light + ambient color on the renderer once during OnLoad,
/// on the render worker. First port from .Legacy DirectionalLight node — multi-light
/// + per-frame light updates come with later examples (point/spot).
/// </summary>
public sealed class LightModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    public Vector3 Direction { get; init; } = new(0.2f, 1f, 0.5f);
    public Vector3 Color     { get; init; } = Vector3.One;
    public float   Intensity { get; init; } = 1f;
    public Vector3 Ambient   { get; init; } = new(0.2f, 0.2f, 0.2f);

    public string Name => "Light";

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;

        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try
            {
                var dir = Vector3.Normalize(Direction);
                renderer.SetDirectionalLight(dir.X, dir.Y, dir.Z, Color.X, Color.Y, Color.Z, Intensity);
                renderer.SetAmbientLight(Ambient.X, Ambient.Y, Ambient.Z);
            }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });

        done.Wait();
        if (err != null) throw new InvalidOperationException($"{Name} setup failed", err);
    }
}
