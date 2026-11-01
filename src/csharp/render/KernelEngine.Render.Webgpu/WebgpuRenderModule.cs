
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
    private readonly System.Numerics.Vector4? _clearColorOverride;
    private readonly uint _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride;
    private readonly bool _debugLabelsOverride, _defaultPasses;
    private readonly bool _enableShadows, _enableIbl;

    /// <param name="shaderDir">
    /// Directory the compiled shaders of every render pass were installed into. Absolute, or
    /// relative to the process working directory. Required.
    /// </param>
    /// <param name="clearColor">
    /// Background color (RGBA). The default value reads <c>[render] clear_color_r/g/b/a</c> from
    /// <see cref="IConfiguration"/> at <see cref="OnLoad"/> instead.
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
        _clearColorOverride = clearColor == default ? null : clearColor;
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
            .AddDefaultRenderService(_shaderDir)
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
        var clearColor = _clearColorOverride ?? ResolveClearColor(services.GetService<IConfiguration>());
        _renderService.SetClearColor(clearColor.X, clearColor.Y, clearColor.Z, clearColor.W);

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

    /// <summary>
    /// Reads the clear color from the four scalar keys <c>[render] clear_color_r/g/b/a</c>, with a
    /// dark blue for a key or a configuration that is absent.
    /// </summary>
    private static System.Numerics.Vector4 ResolveClearColor(IConfiguration? config)
    {
        const float defaultR = 0.10f, defaultG = 0.15f, defaultB = 0.30f, defaultA = 1.0f;
        if (config is null) return new(defaultR, defaultG, defaultB, defaultA);
        return new(
            (float)config.GetDouble("render", "clear_color_r", defaultR),
            (float)config.GetDouble("render", "clear_color_g", defaultG),
            (float)config.GetDouble("render", "clear_color_b", defaultB),
            (float)config.GetDouble("render", "clear_color_a", defaultA));
    }

    /// <summary>
    /// Uploads an interleaved mesh (position and normal vertices, 16-bit indices) to GPU buffers
    /// owned by the render service and returns the handle a <see cref="MeshComponent"/> refers to.
    /// Throws <see cref="InvalidOperationException"/> before the module is loaded.
    /// </summary>
    public MeshHandle UploadMesh(string key, ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices)
    {
        if (_renderService == null)
            throw new InvalidOperationException("UploadMesh called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        fixed (MeshVertex* v = vertices)
        {
            var h = _renderService.UploadMesh(key, (nint)v, (nuint)(vertices.Length * sizeof(MeshVertex)), indices);
            return h;
        }
    }

    /// <inheritdoc/>
    public TextureHandle UploadTexture(string key, uint width, uint height, ReadOnlySpan<byte> rgba)
    {
        if (_renderService == null)
            throw new InvalidOperationException("UploadTexture called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        fixed (byte* p = rgba)
        {
            var h = _renderService.UploadTexture(key, width, height, (nint)p);
            return h;
        }
    }

    /// <inheritdoc/>
    public TextureHandle UploadCubemap(string key, uint faceSize, ReadOnlySpan<byte> faces)
    {
        if (_renderService == null)
            throw new InvalidOperationException("UploadCubemap called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        fixed (byte* p = faces)
        {
            var h = _renderService.UploadCubemap(key, faceSize, (nint)p);
            return h;
        }
    }

    /// <inheritdoc/>
    public MaterialHandle CreateMaterial(string key, System.Numerics.Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                         TextureHandle? albedo = null, TextureHandle? normalMap = null,
                                         AlphaMode alphaMode = AlphaMode.Opaque, float alphaCutoff = 0.5f,
                                         float ior = 1.5f, float distortionStrength = 0.05f,
                                         string? shader = null)
    {
        if (_renderService == null)
            throw new InvalidOperationException("CreateMaterial called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        var albedoH = albedo ?? new TextureHandle { Bits = uint.MaxValue };
        var normalH = normalMap ?? new TextureHandle { Bits = uint.MaxValue };
        var h = _renderService.CreateMaterial(key, (nint)(&baseColor.X), metallic, roughness, albedoH, normalH,
            alphaMode, alphaCutoff, ior, distortionStrength, shader ?? "");
        return h;
    }

    /// <summary>
    /// The render service pointer, untyped, for native calls that cross into another plugin.
    /// </summary>
    void* INativeRenderResources.Native => _core;

    /// <inheritdoc/>
    public TextureHandle WhiteTexture
    {
        get
        {
            if (_renderService == null)
                throw new InvalidOperationException("WhiteTexture read before the render module was loaded");
            return _renderService.WhiteTexture();
        }
    }

    /// <inheritdoc/>
    public void RetainMesh(MeshHandle h) => _renderService!.RetainMesh(h);
    /// <inheritdoc/>
    public void ReleaseMesh(MeshHandle h) => _renderService!.ReleaseMesh(h);
    /// <inheritdoc/>
    public void RetainTexture(TextureHandle h) => _renderService!.RetainTexture(h);
    /// <inheritdoc/>
    public void ReleaseTexture(TextureHandle h) => _renderService!.ReleaseTexture(h);
    /// <inheritdoc/>
    public void RetainMaterial(MaterialHandle h) => _renderService!.RetainMaterial(h);
    /// <inheritdoc/>
    public void ReleaseMaterial(MaterialHandle h) => _renderService!.ReleaseMaterial(h);

    /// <inheritdoc/>
    public bool TryGetMesh(string key, out MeshHandle handle)
    {
        var found = _renderService!.TryGetMesh(key, out var h);
        handle = h;
        return found;
    }

    /// <inheritdoc/>
    public bool TryGetTexture(string key, out TextureHandle handle)
    {
        var found = _renderService!.TryGetTexture(key, out var h);
        handle = h;
        return found;
    }

    /// <inheritdoc/>
    public bool TryGetMaterial(string key, out MaterialHandle handle)
    {
        var found = _renderService!.TryGetMaterial(key, out var h);
        handle = h;
        return found;
    }

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
        KernelEngine.Render.Native.ke_ui_font_handle h;
        fixed (byte* k = keyBytes)
            KernelEngine.NativeResults.ThrowIfFailed(_ui->load_font(_ui, (sbyte*)k, texH, native, (uint)glyphs.Length, lineHeight, ascent, &h), "load_font");
        return new FontHandle(h.bits);
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
