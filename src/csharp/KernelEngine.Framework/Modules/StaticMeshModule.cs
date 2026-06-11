using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Contributes a single static mesh draw to every frame packet. The setup
/// delegate runs once on the render worker during OnLoad and returns the
/// mesh + material handles; from then on the module just emits one
/// <see cref="IFramePacket.AddDrawCommand"/> per tick.
/// </summary>
public sealed class StaticMeshModule : IRuntimeModule, IFrameContributor
{
    private const uint RenderWorker = 1;

    private readonly Func<IRenderer, (MeshHandle Mesh, MaterialHandle Material)> _setup;
    private readonly Matrix4x4 _transform;

    private MeshHandle     _mesh;
    private MaterialHandle _material;
    private bool           _ready;

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

    public void Configure(IServiceCollection services) => services.AddSingleton<IFrameContributor>(this);

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;

        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { (_mesh, _material) = _setup(renderer); _ready = true; }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });

        done.Wait();
        if (err != null) throw new InvalidOperationException("StaticMesh setup failed", err);
    }

    public void Contribute(IFramePacket packet)
    {
        if (!_ready) return;
        packet.AddDrawCommand(_mesh, _material, _transform);
    }
}
