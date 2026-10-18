using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Framework;
using KernelEngine.Logger;
using KernelEngine.Render;
using KernelEngine.Render.Native;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;
using KernelEngine.Text.Native;
using KernelEngine.Window;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device and a
/// render target presenting into the window, and installs the render path (ke_render_module) which
/// registers begin/clear/end as KE_PHASE_RENDER systems on the runtime. The host
/// just ticks the runtime — no render calls in the loop.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources, INativeRenderResources
{
    private ke_gpu_device_handle _device;
    private ke_gpu_render_target_handle _target;
    private ke_render_module_handle _module;
    private ke_render_service* _core;
    private RenderService? _renderService;
    private readonly string _shaderDir;
    private readonly System.Numerics.Vector4? _clearColorOverride;
    private readonly uint _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride;
    private readonly bool _debugLabelsOverride;
    private readonly ke_render_feature_params _featureParams;

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
    /// native module.
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
    public WebgpuRenderModule(string shaderDir, System.Numerics.Vector4 clearColor = default,
        uint clusterGridX = 0, uint clusterGridY = 0, uint clusterGridZ = 0, uint maxLightsPerCluster = 0,
        bool enableShadows = true, bool enableIbl = true, bool debugLabels = false)
    {
        _debugLabelsOverride = debugLabels;
        ArgumentException.ThrowIfNullOrEmpty(shaderDir);
        _shaderDir = shaderDir;
        _clearColorOverride = clearColor == default ? null : clearColor;
        _clusterGridXOverride = clusterGridX;
        _clusterGridYOverride = clusterGridY;
        _clusterGridZOverride = clusterGridZ;
        _maxLightsPerClusterOverride = maxLightsPerCluster;
        _featureParams = new ke_render_feature_params
        {
            enable_shadows = enableShadows,
            enable_ibl = enableIbl,
        };
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
    }

    /// <summary>
    /// Creates the device, the window target and the render module. The window target presents
    /// with vertical sync unless <c>[runtime.renderer] vsync</c> is false in
    /// <see cref="IConfiguration"/>, in which case frames are shown at once.
    /// </summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window = services.GetRequiredService<IWindow>();
        var ecs = services.GetRequiredService<INativeEcs>();
        var logger = services.GetService<INativeLogger>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var world = services.GetService<KernelEngine.Framework.World>();

        var win = ((INativeWindow)window).Native;
        var rt = ((INativeRuntime)runtime).Native;
        var ec = ecs.Native;
        var lg = logger != null ? logger.Native : null;
        var sc = ((INativeScheduler)scheduler).Native;
        var wd = world != null ? ((KernelEngine.Framework.INativeWorld)world).Native : null;

        ke_error* err = null;

        var config = services.GetService<IConfiguration>();
        var debugLabels = _debugLabelsOverride || (config?.GetBool("render", "debug_labels", false) ?? false);
        var dp = new ke_gpu_device_webgpu_params { enable_validation = true, scheduler = sc, debug_labels = debugLabels };
        _device = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, &err);
        if (_device.@ref == null)
            throw Fail("webgpu device create failed", err);

        var vsync = config?.GetBool("runtime.renderer", "vsync", true) ?? true;
        var tp = new ke_gpu_render_target_webgpu_window_params
        {
            device = _device.@ref,
            window = win,
            present_mode = vsync ? ke_gpu_present_mode.KE_GPU_PRESENT_MODE_FIFO : ke_gpu_present_mode.KE_GPU_PRESENT_MODE_IMMEDIATE,
        };
        _target = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_render_target_webgpu_window_create(&tp, &err);
        if (_target.@ref == null)
            throw Fail("webgpu window render target create failed", err);

        var cp = new ke_render_cluster_grid
        {
            grid_x = _clusterGridXOverride != 0 ? _clusterGridXOverride : (uint)(config?.GetInt("render", "cluster_grid_x", 0) ?? 0),
            grid_y = _clusterGridYOverride != 0 ? _clusterGridYOverride : (uint)(config?.GetInt("render", "cluster_grid_y", 0) ?? 0),
            grid_z = _clusterGridZOverride != 0 ? _clusterGridZOverride : (uint)(config?.GetInt("render", "cluster_grid_z", 0) ?? 0),
            max_lights_per_cluster = _maxLightsPerClusterOverride != 0
                ? _maxLightsPerClusterOverride
                : (uint)(config?.GetInt("render", "max_lights_per_cluster", 0) ?? 0),
        };
        var fp = _featureParams;
        var ar = services.GetService<KernelEngine.Framework.NativeAssetResolver>() is { } resolver
            ? (KernelEngine.Asset.Native.ke_asset_resolver*)((KernelEngine.Framework.INativeAssetResolver)resolver).Native
            : null;
        var shaderDirBytes = System.Text.Encoding.UTF8.GetBytes(_shaderDir + '\0');
        fixed (byte* sd = shaderDirBytes)
            _module = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_create(rt, ec, _device.@ref, _target.@ref, wd, true, lg, ar, &cp, &fp, null, null, null, (sbyte*)sd, &err);
        if (_module.@ref == null)
            throw Fail("render module create failed", err);

        _core = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_core(_module.@ref);
        _renderService = RenderService.Borrow(_core);
        var clearColor = _clearColorOverride ?? ResolveClearColor(config);
        _renderService.SetClearColor(clearColor.X, clearColor.Y, clearColor.Z, clearColor.W);

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
        fixed (ushort* i = indices)
        {
            var h = _renderService.UploadMesh(key, v, (nuint)(vertices.Length * sizeof(MeshVertex)), i, (uint)indices.Length);
            return new MeshHandle(h.bits);
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
            var h = _renderService.UploadTexture(key, width, height, p);
            return new TextureHandle(h.bits);
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
            var h = _renderService.UploadCubemap(key, faceSize, p);
            return new TextureHandle(h.bits);
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

        var albedoH = new ke_texture_handle { bits = albedo?.Value ?? uint.MaxValue };
        var normalH = new ke_texture_handle { bits = normalMap?.Value ?? uint.MaxValue };
        var h = _renderService.CreateMaterial(key, &baseColor.X, metallic, roughness, albedoH, normalH,
            (ke_alpha_mode)(int)alphaMode, alphaCutoff, ior, distortionStrength, shader ?? "");
        return new MaterialHandle(h.bits);
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
            return new TextureHandle(_renderService.WhiteTexture().bits);
        }
    }

    /// <inheritdoc/>
    public void RetainMesh(MeshHandle h) => _renderService!.RetainMesh(new ke_mesh_handle { bits = h.Value });
    /// <inheritdoc/>
    public void ReleaseMesh(MeshHandle h) => _renderService!.ReleaseMesh(new ke_mesh_handle { bits = h.Value });
    /// <inheritdoc/>
    public void RetainTexture(TextureHandle h) => _renderService!.RetainTexture(new ke_texture_handle { bits = h.Value });
    /// <inheritdoc/>
    public void ReleaseTexture(TextureHandle h) => _renderService!.ReleaseTexture(new ke_texture_handle { bits = h.Value });
    /// <inheritdoc/>
    public void RetainMaterial(MaterialHandle h) => _renderService!.RetainMaterial(new ke_material_handle { bits = h.Value });
    /// <inheritdoc/>
    public void ReleaseMaterial(MaterialHandle h) => _renderService!.ReleaseMaterial(new ke_material_handle { bits = h.Value });

    /// <inheritdoc/>
    public bool TryGetMesh(string key, out MeshHandle handle)
    {
        var found = _renderService!.TryGetMesh(key, out var h);
        handle = new MeshHandle(h.bits);
        return found;
    }

    /// <inheritdoc/>
    public bool TryGetTexture(string key, out TextureHandle handle)
    {
        var found = _renderService!.TryGetTexture(key, out var h);
        handle = new TextureHandle(h.bits);
        return found;
    }

    /// <inheritdoc/>
    public bool TryGetMaterial(string key, out MaterialHandle handle)
    {
        var found = _renderService!.TryGetMaterial(key, out var h);
        handle = new MaterialHandle(h.bits);
        return found;
    }

    /// <inheritdoc/>
    public FontHandle LoadFont(string key, TextureHandle atlas, ReadOnlySpan<FontGlyph> glyphs,
                               float lineHeight, float ascent)
    {
        if (_module.@ref == null)
            throw new InvalidOperationException("LoadFont called before the render module was loaded");
        ArgumentException.ThrowIfNullOrEmpty(key);

        var keyBytes = System.Text.Encoding.UTF8.GetBytes(key + '\0');
        var native = stackalloc ke_glyph_metrics[glyphs.Length];
        for (int i = 0; i < glyphs.Length; i++)
        {
            var g = glyphs[i];
            native[i] = new ke_glyph_metrics
            {
                codepoint = g.Codepoint,
                u0 = g.U0,
                v0 = g.V0,
                u1 = g.U1,
                v1 = g.V1,
                bearing_x = g.BearingX,
                bearing_y = g.BearingY,
                width = g.Width,
                height = g.Height,
                advance_x = g.AdvanceX,
            };
        }

        var texH = new ke_texture_handle { bits = atlas.Value };
        ke_error* err = null;
        KernelEngine.Render.Native.ke_ui_font_handle h;
        fixed (byte* k = keyBytes)
            h = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_load_font(
                _module.@ref, (sbyte*)k, texH, native, (uint)glyphs.Length, lineHeight, ascent, &err);
        if (h.bits == uint.MaxValue)
            throw Fail("load_font failed", err);
        return new FontHandle(h.bits);
    }

    /// <summary>Builds the exception for a failed native call, with the native error's type and message when there is one.</summary>
    private static InvalidOperationException Fail(string what, ke_error* err)
    {
        if (err != null)
        {
            var msg = Marshal.PtrToStringUTF8((IntPtr)err->message) ?? "(no message)";
            var name = err->type != null ? Marshal.PtrToStringUTF8((IntPtr)err->type->name) ?? "?" : "?";
            return new InvalidOperationException($"{what} [{name}]: {msg}");
        }
        return new InvalidOperationException(what);
    }

    /// <summary>Destroys the render module, then the render target, then the device, skipping any that was never created.</summary>
    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_module.@ref != null && _module.destroy != null)
            _module.destroy(_module.@ref);
        if (_target.@ref != null && _target.destroy != null)
            _target.destroy(_target.@ref);
        if (_device.@ref != null && _device.destroy != null)
            _device.destroy(_device.@ref);
    }
}
