using System.Numerics;

using KernelEngine.Framework;
using KernelEngine.Render;
using KernelEngine.Render.Webgpu;
using KernelEngine.View;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace KernelEngine;

/// <summary>
/// The default passes, made over the registered render service, camera, scene and frame: shadows, clusters, the
/// gbuffer, deferred and forward lighting, tonemapping, the UI and its labels. Disposing it releases them, the
/// last made first.
/// </summary>
public sealed class DefaultRenderer : IEnginePart, IDisposable
{
    readonly IDisposable[] _passes;

    /// <summary>Makes the passes from the parts <paramref name="services"/> holds.</summary>
    /// <param name="services">The container the render parts are registered in.</param>
    /// <param name="defaultFont">The font a label falls back to.</param>
    public DefaultRenderer(IServiceProvider services, string defaultFont)
    {
        var log = services.GetService<ILoggerFactory>();
        var runtime = services.GetRequiredService<Runtime.Runtime>();
        var ecs = services.GetRequiredService<Ecs.EcsRegistry>();
        var service = services.GetRequiredService<RenderService>();
        var gpu = services.GetRequiredService<Render.Gpu.GpuDevice>();
        var viewSpace = services.GetRequiredService<ViewSpace>();
        var camera = services.GetRequiredService<RenderCamera>();
        var scene = services.GetRequiredService<RenderSceneResolve>();
        var frame = services.GetRequiredService<RenderFrame>();
        var assets = services.GetRequiredService<AssetResolver>();
        var shadow = new RenderShadow(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame, new() { Resolution = 1024, LightDistance = 25.0f, Extent = 20.0f, NearPlane = 0.1f, FarPlane = 50.0f });
        var cluster = new RenderCluster(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame, new() { GridX = 16, GridY = 9, GridZ = 24, MaxLightsPerCluster = 64 });
        var gbuffer = new RenderGbuffer(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
        var ui = new DefaultRenderUi(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame);
        _passes =
        [
            shadow, cluster, gbuffer,
            new RenderDeferredLighting(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame, gbuffer.Resources, shadow.Resources, cluster.Resources, new() { IblEnabled = true }),
            new RenderForward(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame, shadow.Resources, cluster.Resources, new() { IblEnabled = true }),
            new RenderTonemap(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame),
            ui,
            new RenderLabelResolve(log, runtime, ecs, service, gpu, viewSpace, camera, scene, frame, ui, assets, new() { DefaultFont = defaultFont }),
        ];
    }

    /// <summary>Releases the passes, the last made first.</summary>
    public void Dispose()
    {
        for (var i = _passes.Length - 1; i >= 0; i--) _passes[i].Dispose();
    }

    /// <summary>The colour the frame is cleared to: <c>render.clear_color</c>, opaque black by default.</summary>
    /// <param name="config">The project file's values.</param>
    public static Vector4 ClearColor(Configuration.Configuration config) => new(
        (float)config.GetDouble("render", "clear_color.0", 0.0),
        (float)config.GetDouble("render", "clear_color.1", 0.0),
        (float)config.GetDouble("render", "clear_color.2", 0.0),
        (float)config.GetDouble("render", "clear_color.3", 1.0));
}
