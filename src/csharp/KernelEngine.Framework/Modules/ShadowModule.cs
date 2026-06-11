using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Opt-in shadow mapping module. Allocates a single directional shadow map at
/// load time and contributes per-frame shadow state + draw commands while the
/// scene is active. Add it to the runtime BEFORE the SceneModule callback
/// runs (Configure-time DI registration happens then) — typically right after
/// <see cref="SceneRenderModule"/>.
/// </summary>
/// <remarks>
/// Only the first <see cref="DirectionalLightComponent"/> casts shadow; point
/// + spot shadows are out of scope until additional shadow maps are wired in.
/// The shadow map lives entirely on the render worker (creation + destroy +
/// per-frame use); the contributor runs on the render worker too as part of
/// the bgfx packet pipeline.
/// </remarks>
public sealed class ShadowModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly uint  _resolution;
    private readonly float _frustumSize;
    private readonly float _farPlane;

    private ShadowResources?  _resources;
    private ShadowMapHandle?  _ownedHandle;

    public string Name => "Shadow";

    public IEnumerable<Type> Dependencies => new[] { typeof(SceneRenderModule) };

    public ShadowModule(uint resolution = 1024, float frustumSize = 20f, float farPlane = 50f)
    {
        _resolution  = resolution;
        _frustumSize = frustumSize;
        _farPlane    = farPlane;
    }

    public void Configure(IServiceCollection services)
    {
        var resources = new ShadowResources
        {
            Resolution  = _resolution,
            FrustumSize = _frustumSize,
            FarPlane    = _farPlane,
        };
        _resources = resources;

        services.AddSingleton(resources);
        services.AddSingleton<IFrameContributor, ShadowContributor>(sp =>
            new ShadowContributor(
                sp.GetRequiredService<EcsAdapter>(),
                sp.GetRequiredService<ComponentRegistry>(),
                resources));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();
        var resources = _resources!;

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try
            {
                var handle = renderer.CreateShadowMap(_resolution, _resolution).Value;
                _ownedHandle    = handle;
                resources.Handle = handle;
            }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err != null)
            throw new InvalidOperationException("Shadow map creation failed", err);
    }

    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_ownedHandle is not { } handle) return;

        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { renderer.DestroyShadowMap(handle); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        _ownedHandle = null;
        if (_resources is { } r) r.Handle = null;
        if (err != null)
            throw new InvalidOperationException("Shadow map destroy failed", err);
    }
}
