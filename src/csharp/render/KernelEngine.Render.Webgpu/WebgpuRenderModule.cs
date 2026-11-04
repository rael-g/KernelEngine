
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
    private readonly string _shaderDir;
    private readonly System.Numerics.Vector4 _clearColor;
    private readonly uint _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride;
    private readonly bool _debugLabelsOverride, _defaultPasses;
    private readonly bool _enableShadows, _enableIbl;

    /// <param name="shaderDir">
    /// Directory the compiled shaders of every render pass were installed into. Absolute, or
    /// relative to the process working directory. Required.
    /// </param>
    /// <param name="clearColor">
    /// Background color (RGBA). The default value leaves it to the render service, which reads
    /// <c>[render] clear_color_r/g/b/a</c> from <see cref="IConfiguration"/>.
    /// </param>
    /// <param name="clusterGridX">
    /// Screen-tile columns of the light grid. Zero reads <c>[render] cluster_grid_x</c> from
    /// <see cref="IConfiguration"/> at <see cref="OnLoad"/>, and a value still zero is left to the
    /// cluster pass.
    /// </param>
    /// <param name="clusterGridY">Rows of the light grid, resolved as <paramref name="clusterGridX"/> with key <c>cluster_grid_y</c>.</param>
    /// <param name="clusterGridZ">Depth slices of the light grid, resolved as <paramref name="clusterGridX"/> with key <c>cluster_grid_z</c>.</param>
    /// <param name="maxLightsPerCluster">
    /// Capacity of the light list of one cluster, resolved as <paramref name="clusterGridX"/> with
    /// key <c>max_lights_per_cluster</c>.
    /// </param>
    /// <param name="enableShadows">When false, no shadow pass and no shadow map render target exist.</param>
    /// <param name="enableIbl">When false, materials sample a black environment whatever skybox exists; the skybox itself still draws.</param>
    /// <param name="debugLabels">
    /// When true, the names of GPU objects, passes and debug groups reach the graphics API. False
    /// reads <c>[render] debug_labels</c> from <see cref="IConfiguration"/> at <see cref="OnLoad"/>.
    /// </param>
    /// <param name="defaultPasses">When false, no pass is registered; the host registers its own, in the order their resources flow.</param>
    public WebgpuRenderModule(string shaderDir, System.Numerics.Vector4 clearColor = default,
        uint clusterGridX = 0, uint clusterGridY = 0, uint clusterGridZ = 0, uint maxLightsPerCluster = 0,
        bool enableShadows = true, bool enableIbl = true, bool debugLabels = false, bool defaultPasses = true)
    {
        _defaultPasses = defaultPasses;
        _debugLabelsOverride = debugLabels;
        ArgumentException.ThrowIfNullOrEmpty(shaderDir);
        _shaderDir = shaderDir;
        _clearColor = clearColor;
        _clusterGridXOverride = clusterGridX;
        _clusterGridYOverride = clusterGridY;
        _clusterGridZOverride = clusterGridZ;
        _maxLightsPerClusterOverride = maxLightsPerCluster;
        _enableShadows = enableShadows;
        _enableIbl = enableIbl;
    }

    public string Name => "Webgpu.Render";

    /// <summary>
    /// Exposes this module as <see cref="IRenderResources"/> and registers the node types of the
    /// render domain.
    /// </summary>
    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<IRenderResources>(this);
        services
            .AddRenderComponentsNodeTypes()
            .AddUiComponentsNodeTypes()
            .AddNodeType<Sprite2D>();
        services
            .AddWebgpuGpuDevice(enableValidation: true, debugLabels: _debugLabelsOverride)
            .AddWebgpuWindowGpuRenderTarget()
            .AddGroupedRenderResourceBinder(_shaderDir)
            .AddDefaultRenderService(_shaderDir, clearColor: _clearColor)
            .AddRhViewSpace()
            .AddDefaultRenderCamera()
            .AddDefaultRenderSceneResolve()
            .AddDefaultRenderFrame();
        if (!_defaultPasses) return;
        if (_enableShadows) services.AddRenderShadow("shadow");
        var shadow = _enableShadows ? "shadow" : null;
        services
            .AddRenderCluster("clusters", _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride)
            .AddRenderGbuffer("gbuffer")
            .AddRenderDeferredLighting(_enableIbl, "gbuffer", shadow, "clusters")
            .AddRenderSkybox()
            .AddRenderForward(_enableIbl, shadow, "clusters")
            .AddRenderTonemap()
            .AddDefaultRenderUi()
            .AddRenderLabelResolve();
    }

    /// <summary>
    /// Creates the device, the window target and the renderer. The window target presents
    /// with vertical sync unless <c>[runtime.renderer] vsync</c> is false in
    /// <see cref="IConfiguration"/>, in which case frames are shown at once.
    /// </summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var core = services.GetRequiredService<INativeRenderService>().Native;
        _core = core;
        _ui = services.GetService<KernelEngine.Render.Webgpu.INativeRenderUi>() is { } ui ? ui.Native : null;
        _renderService = RenderService.Borrow(core);
        foreach (var pass in services.GetServices<IRuntimeModule>().OfType<IResolveOnLoad>().ToList())
            pass.Resolve(services);

        if (services.GetService<KernelEngine.Framework.World>() is not { } world)
            return;
        var ec = services.GetRequiredService<INativeEcs>().Native;
        var wd = ((KernelEngine.Framework.INativeWorld)world).Native;
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
