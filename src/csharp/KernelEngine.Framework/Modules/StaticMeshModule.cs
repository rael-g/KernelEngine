using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Submits a single static mesh + material with a fixed transform every Update
/// tick. Pinned to the render worker. First minimal port of .Legacy MeshRenderer
/// node + MeshRenderSystem — full ECS-driven mesh component + per-entity systems
/// land when an example needs multiple meshes.
/// </summary>
/// <remarks>
/// Setup delegate is invoked once during OnLoad on the render worker and returns
/// the mesh + material handles. Use it to create the texture / material / mesh
/// from the bgfx-thread side; the captured handles are then submitted every frame.
/// </remarks>
public sealed class StaticMeshModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly Func<IRenderer, (MeshHandle Mesh, MaterialHandle Material)> _setup;
    private readonly Matrix4x4 _transform;

    public string Name => "StaticMesh";

    /// <param name="setup">Runs on the render worker during OnLoad; returns the mesh + material to submit each frame.</param>
    /// <param name="transform">World transform applied to the mesh every submit (default identity).</param>
    public StaticMeshModule(
        Func<IRenderer, (MeshHandle Mesh, MaterialHandle Material)> setup,
        Matrix4x4? transform = null)
    {
        _setup     = setup;
        _transform = transform ?? Matrix4x4.Identity;
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();

        MeshHandle     mesh = default;
        MaterialHandle mat  = default;
        Exception?     err  = null;
        var done = new System.Threading.ManualResetEventSlim(false);

        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { (mesh, mat) = _setup(renderer); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });

        done.Wait();
        if (err != null) throw new InvalidOperationException("StaticMesh setup failed", err);

        runtime.RegisterSystem("StaticMesh.Submit", RuntimePhase.Update, (_, _) =>
        {
            renderer.SubmitMesh(mesh, mat, _transform);
        }, pinnedThread: RenderWorker);
    }
}
