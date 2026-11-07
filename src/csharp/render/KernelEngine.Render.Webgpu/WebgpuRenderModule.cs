
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Framework;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Render.Native;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.TaskPool;
using KernelEngine.Text.Native;
using KernelEngine.View;
using KernelEngine.Window;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device and a render
/// target presenting into the window, and composes the renderer on the runtime: the render
/// service, the camera, the scene resolve, the frame, the shadow, cluster, gbuffer, deferred
/// lighting, skybox, forward, tonemap and ui passes, and the label resolve. The host just ticks
/// the runtime; no render calls in the loop.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources, INativeRenderResources
{
    private ke_render_service* _core;
    private ke_render_ui* _ui;
    private RenderService? _renderService;
    private readonly bool _defaultPasses;
    private readonly bool _enableShadows, _enableIbl;

    /// <param name="enableShadows">When false, no shadow pass and no shadow map render target exist.</param>
    /// <param name="enableIbl">When false, materials sample a black environment whatever skybox exists; the skybox itself still draws.</param>
    /// <param name="defaultPasses">When false, no pass is registered; the host registers its own, in the order their resources flow.</param>
    public WebgpuRenderModule(bool enableShadows = true, bool enableIbl = true, bool defaultPasses = true)
    {
        _defaultPasses = defaultPasses;
        _enableShadows = enableShadows;
        _enableIbl = enableIbl;
    }

    public string Name => "Webgpu.Render";

    /// <summary>
    /// Exposes this module as <see cref="IRenderResources"/>, registers the node types of the
    /// render domain and the renderer's parts, each created with the config registered for it or
    /// its defaults; the resource binder reads its shaders from the <c>ShaderDir</c> of the registered
    /// <see cref="DefaultRenderServiceConfig"/>.
    /// </summary>
    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<IRenderResources>(this);
        services
            .AddRenderComponentsNodeTypes()
            .AddUiComponentsNodeTypes()
            .AddNodeType<Sprite2D>();
        services
            .AddWebgpuGpuDevice()
            .AddWebgpuWindowGpuRenderTarget()
            .AddDefaultRenderService();
        services.AddSingleton(sp =>
        {
            var shaderDir = sp.GetService<Microsoft.Extensions.Options.IOptions<DefaultRenderServiceConfig>>()?.Value.ShaderDir;
            var device = sp.GetRequiredService<KernelEngine.Render.Gpu.INativeGpuDevice>();
            var io = sp.GetRequiredService<KernelEngine.Io.INativeIo>();
            return sp.GetService<Microsoft.Extensions.Logging.ILoggerFactory>() is { } loggerFactory
                ? new GroupedRenderResourceBinder(loggerFactory, device, shaderDir, io)
                : new GroupedRenderResourceBinder(device, shaderDir, io);
        });
        services.AddSingleton<KernelEngine.Render.Gpu.INativeRenderResourceBinder>(sp => sp.GetRequiredService<GroupedRenderResourceBinder>());
        services
            .AddRhViewSpace()
            .AddDefaultRenderCamera()
            .AddDefaultRenderSceneResolve()
            .AddDefaultRenderFrame();
        if (!_defaultPasses) return;
        if (_enableShadows) services.AddRenderShadow("shadow");
        var shadow = _enableShadows ? "shadow" : null;
        services
            .AddRenderCluster("clusters")
            .AddRenderGbuffer("gbuffer")
            .AddRenderDeferredLighting(_enableIbl, "gbuffer", shadow, "clusters")
            .AddRenderSkybox()
            .AddRenderForward(_enableIbl, shadow, "clusters")
            .AddRenderTonemap()
            .AddDefaultRenderUi()
            .AddRenderLabelResolve();
    }

    /// <summary>
    /// Creates the device, the window target and the renderer, each with the config registered
    /// for it or its defaults.
    /// </summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var core = services.GetRequiredService<INativeRenderService>().Native;
        _core = core;
        _ui = services.GetService<KernelEngine.Render.Webgpu.INativeRenderUi>() is { } ui ? ui.Native : null;
        _renderService = RenderService.Borrow(core);
        foreach (var pass in services.GetServices<IRuntimeModule>().OfType<IResolveOnLoad>().ToList())
            pass.Resolve(services);

        if (services.GetService<KernelEngine.Framework.ComponentRegistry>() is not { } registry)
            return;
        var ec = services.GetRequiredService<INativeEcs>().Native;
        var wd = ((KernelEngine.Framework.INativeComponentRegistry)registry).Native;
        KernelEngine.Framework.Native.ke_scene_component_set_handle set;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Framework.Native.NativeMethods.scene_component_set_create(&set), "ke_scene_component_set_create");
        try
        {
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_scene_components_create(set.@ref), "ke_render_scene_components_create");
            KernelEngine.NativeResults.ThrowIfFailed(set.@ref->register_into(set.@ref, ec, wd), "register_into");
        }
        finally
        {
            set.destroy(set.@ref);
        }
    }

    /// <inheritdoc/>
    public TextureHandle UploadTexture(string key, uint width, uint height, ReadOnlySpan<byte> rgba)
    {
        if (_renderService == null)
            throw new InvalidOperationException("UploadTexture called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        return _renderService.UploadTexture(key, width, height, rgba);
    }

    /// <summary>
    /// The render service pointer, untyped, for native calls that cross into another plugin.
    /// </summary>
    void* INativeRenderResources.Native => _core;

    /// <inheritdoc/>
    public FontHandle LoadFont(string key, TextureHandle atlas, ReadOnlySpan<FontGlyph> glyphs,
                               float lineHeight, float ascent)
    {
        if (_ui == null)
            throw new InvalidOperationException("LoadFont called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        var keyBytes = System.Text.Encoding.UTF8.GetBytes(key + '\0');
        var native = stackalloc KernelEngine.Text.GlyphMetrics[glyphs.Length];
        for (int i = 0; i < glyphs.Length; i++)
        {
            var g = glyphs[i];
            native[i] = new KernelEngine.Text.GlyphMetrics
            {
                Codepoint = g.Codepoint,
                U0 = g.U0,
                V0 = g.V0,
                U1 = g.U1,
                V1 = g.V1,
                BearingX = g.BearingX,
                BearingY = g.BearingY,
                Width = g.Width,
                Height = g.Height,
                AdvanceX = g.AdvanceX,
            };
        }

        var texH = atlas;
        UiFontHandle h;
        fixed (byte* k = keyBytes)
            KernelEngine.NativeResults.ThrowIfFailed(_ui->load_font(_ui, (sbyte*)k, texH, native, (uint)glyphs.Length, lineHeight, ascent, &h), "load_font");
        return new FontHandle(h.Bits);
    }

    /// <summary>
    /// Destroys the renderer's pieces in the reverse of their creation, then the render target,
    /// then the device, skipping any that was never created.
    /// </summary>
    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        _renderService = null;
        _core = null;
        _ui = null;
    }
}
