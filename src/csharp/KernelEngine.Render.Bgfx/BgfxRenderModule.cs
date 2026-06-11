using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Bgfx;

/// <summary>
/// bgfx renderer as an <see cref="IRuntimeModule"/>. Pins worker 1 as the
/// "ke.render" thread, runs <c>Initialize</c> on it during OnLoad, then
/// registers <c>ClearColor</c> + <c>Frame</c> as pinned-to-worker-1 systems.
/// The runtime never knows what bgfx is — it sees opaque pinned systems.
/// </summary>
public sealed class BgfxRenderModule : IRuntimeModule
{
    /// <summary>Worker id that becomes "ke.render". Worker 1 is the first dedicated worker; bgfx is single-threaded so one worker is enough.</summary>
    private const uint RenderWorker = 1;

    private readonly string _shaderPath;
    private readonly bool   _vsync;
    private readonly (float r, float g, float b, float a)? _clearColor;

    public string Name => "Bgfx.Render";

    public BgfxRenderModule(string shaderPath, bool vsync = true,
                            (float r, float g, float b, float a)? clearColor = null)
    {
        _shaderPath = shaderPath;
        _vsync      = vsync;
        _clearColor = clearColor;
    }

    public void Configure(IServiceCollection services)
    {
        services.AddBgfxRenderer(_shaderPath, _vsync);
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        if (scheduler.NumWorkers < RenderWorker)
            throw new InvalidOperationException(
                $"BgfxRenderModule needs at least {RenderWorker} worker thread(s); scheduler has {scheduler.NumWorkers}.");

        // Step 1: name worker 1 as "ke.render" via a fire-and-forget pinned task.
        // bgfx's Initialize + Frame assertions check the current thread name; once
        // named, every pinned-to-worker-1 dispatch lands on a thread named "ke.render".
        scheduler.DispatchPinned(RenderWorker, () => KernelThread.SetCurrentName("ke.render"));

        // Step 2: Initialize the renderer on worker 1 and wait synchronously
        // (Initialize must finish before Frame/ClearColor systems register).
        var initDone = new System.Threading.ManualResetEventSlim(false);
        Exception? initError = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { services.GetRequiredService<IRenderer>().Initialize(); }
            catch (Exception ex) { initError = ex; }
            finally { initDone.Set(); }
        });
        initDone.Wait();
        if (initError != null)
            throw new InvalidOperationException("Bgfx renderer Initialize failed", initError);

        // Step 3: register the per-frame render systems, pinned to the same worker.
        // ClearColor in Update (before Extract); Frame in Extract (last phase).
        var renderer = services.GetRequiredService<IRenderer>();

        if (_clearColor is { } c)
        {
            runtime.RegisterSystem("Bgfx.ClearColor", RuntimePhase.Update, (_, _) =>
            {
                renderer.ClearColor(c.r, c.g, c.b, c.a);
            }, pinnedThread: RenderWorker);
        }

        runtime.RegisterSystem("Bgfx.Frame", RuntimePhase.Extract, (_, _) =>
        {
            renderer.Frame();
        }, pinnedThread: RenderWorker);
    }
}
