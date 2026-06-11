using KernelEngine.Framework;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Bgfx;

/// <summary>
/// bgfx renderer as an <see cref="IRuntimeModule"/>. Owns the FrameSync ring,
/// drives a full per-tick packet pipeline (BeginWrite → contributors fill →
/// EndWrite → BeginRead → SubmitPacket → Frame → EndRead). Pins everything to
/// worker 1, which is named "ke.render" at OnLoad time so bgfx's affinity
/// assertions pass.
/// </summary>
/// <remarks>
/// TECH DEBT: the packet pipeline is here because the native renderer's
/// <c>submit_mesh</c> / per-state setters are stubs (see
/// <see cref="IFrameContributor"/> remarks). When the renderer is rewritten to
/// accumulate state per-call, this module collapses to direct setters and the
/// FrameSync + contributors machinery goes away. Game code never sees the
/// packet — only framework modules talk to it.
/// </remarks>
public sealed class BgfxRenderModule : IRuntimeModule
{
    private const uint RenderWorker = 1;

    private readonly string _shaderPath;
    private readonly bool   _vsync;
    private readonly (float r, float g, float b, float a)? _defaultClearColor;

    public string Name => "Bgfx.Render";

    public BgfxRenderModule(string shaderPath, bool vsync = true,
                            (float r, float g, float b, float a)? clearColor = null)
    {
        _shaderPath        = shaderPath;
        _vsync             = vsync;
        _defaultClearColor = clearColor;
    }

    public void Configure(IServiceCollection services)
    {
        services.AddBgfxRenderer(_shaderPath, _vsync);
        services.AddSingleton<IFrameSync>(sp =>
            sp.GetRequiredService<IKernelFactory>()
              .CreateFrameSync(sp.GetRequiredService<Allocator>(), bufferCount: 2));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        if (scheduler.NumWorkers < RenderWorker)
            throw new InvalidOperationException(
                $"BgfxRenderModule needs at least {RenderWorker} worker(s); scheduler has {scheduler.NumWorkers}.");

        // Name worker 1 "ke.render" so bgfx affinity assertions pass.
        scheduler.DispatchPinned(RenderWorker, () => KernelThread.SetCurrentName("ke.render"));

        // Initialize renderer synchronously on the render worker.
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

        // Full per-tick render pipeline runs in Extract phase, pinned. Order:
        //   1. Open packet (BeginWrite).
        //   2. Default clear color (module config).
        //   3. Resolve every IFrameContributor and let it write its per-frame data.
        //   4. Close packet (EndWrite).
        //   5. Swap to reader side (BeginRead), SubmitPacket, Frame, EndRead.
        var renderer     = services.GetRequiredService<IRenderer>();
        var frameSync    = services.GetRequiredService<IFrameSync>();
        var contributors = services.GetServices<IFrameContributor>().ToArray();

        runtime.RegisterSystem("Bgfx.RenderFrame", RuntimePhase.Extract, (_, _) =>
        {
            var packet = frameSync.BeginWrite();
            try
            {
                if (_defaultClearColor is { } c)
                    packet.SetClearColor(c.r, c.g, c.b, c.a);

                foreach (var contributor in contributors)
                    contributor.Contribute(packet);
            }
            finally
            {
                packet.EndWrite();
            }

            var readPacket = frameSync.BeginRead();
            try
            {
                renderer.SubmitPacket(readPacket);
                renderer.Frame();
            }
            finally
            {
                readPacket.EndRead();
            }
        }, pinnedThread: RenderWorker);
    }

    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        // bgfx destroy MUST run on the same worker that called bgfx::init (the
        // render worker), so dispatch the renderer's IDisposable.Dispose there
        // and block until it completes. Skipping this would either trip the
        // ke.render affinity assertion on the main thread or — worse, if the
        // assertion were removed — corrupt bgfx's internal state on shutdown.
        var scheduler = services.GetRequiredService<ITaskScheduler>();
        var renderer  = services.GetRequiredService<IRenderer>();

        var done = new System.Threading.ManualResetEventSlim(false);
        Exception? err = null;
        scheduler.DispatchPinned(RenderWorker, () =>
        {
            try   { (renderer as IDisposable)?.Dispose(); }
            catch (Exception ex) { err = ex; }
            finally { done.Set(); }
        });
        done.Wait();
        if (err != null)
            throw new InvalidOperationException("Bgfx renderer Dispose failed", err);
    }
}
