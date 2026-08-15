using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Configuration;
using KernelEngine.Ecs;
using KernelEngine.Framework;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Scheduler;
using KernelEngine.Window;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device
/// from the window and installs the render path (ke_render_module) which
/// registers begin/clear/end as KE_PHASE_RENDER systems on the runtime. The host
/// just ticks the runtime — no render calls in the loop.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources, INativeRenderResources
{
    private ke_gpu_device_handle _device;
    private ke_render_module_handle _module;
    private ke_render_service* _core;
    private RenderService? _renderService;
    private readonly string _shaderDir;
    private readonly System.Numerics.Vector4? _clearColorOverride;
    private readonly uint _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride;
    private readonly ke_render_feature_params _featureParams;

    /// <param name="shaderDir">
    /// Absolute (or process-CWD-relative) path to the directory every render pass's
    /// build-time-compiled shaders were installed into by CMake's
    /// ke_compile_slang_shader (<c>&lt;cmake build dir&gt;/bin/shaders</c>). No
    /// default — a game must know where its own build placed this.
    /// </param>
    /// <param name="clearColor">
    /// Explicit background color override (RGBA), bypassing the Project file. Default
    /// (all-zero) reads <c>[render] clear_color_r/g/b/a</c> from <see cref="IConfiguration"/>
    /// at <see cref="OnLoad"/> instead, falling back to a dark blue if that's absent too.
    /// </param>
    /// <param name="clusterGridX">
    /// Clustered-forward screen-tile columns, bypassing the Project file. 0 (default) reads
    /// <c>[render] cluster_grid_x</c> from <see cref="IConfiguration"/> at <see cref="OnLoad"/>
    /// instead; if that's also absent, the native module applies its own default (32).
    /// </param>
    /// <param name="clusterGridY">Same as <paramref name="clusterGridX"/>, key <c>cluster_grid_y</c>, native default 18.</param>
    /// <param name="clusterGridZ">Same as <paramref name="clusterGridX"/>, key <c>cluster_grid_z</c>, native default 24.</param>
    /// <param name="maxLightsPerCluster">
    /// Per-froxel light-index-list cap, bypassing the Project file. 0 (default) reads
    /// <c>[render] max_lights_per_cluster</c> from config; native default 256 if absent there
    /// too. Raise this for scenes denser than the default sweet spot.
    /// </param>
    /// <param name="enableShadows">When false, no shadow pass and no shadow map render target exist — a game without shadows carries zero shadow-pass footprint. Default true (matches prior behavior).</param>
    /// <param name="enableIbl">When false, materials sample a forced-black environment regardless of any skybox (no ambient/reflection contribution). Skybox rendering itself is unaffected. Default true (matches prior behavior).</param>
    public WebgpuRenderModule(string shaderDir, System.Numerics.Vector4 clearColor = default,
        uint clusterGridX = 0, uint clusterGridY = 0, uint clusterGridZ = 0, uint maxLightsPerCluster = 0,
        bool enableShadows = true, bool enableIbl = true)
    {
        ArgumentException.ThrowIfNullOrEmpty(shaderDir);
        _shaderDir = shaderDir;
        _clearColorOverride = clearColor == default ? null : clearColor;
        _clusterGridXOverride = clusterGridX;
        _clusterGridYOverride = clusterGridY;
        _clusterGridZOverride = clusterGridZ;
        _maxLightsPerClusterOverride = maxLightsPerCluster;
        _featureParams = new ke_render_feature_params
        {
            enable_shadows = (byte)(enableShadows ? 1 : 0),
            enable_ibl = (byte)(enableIbl ? 1 : 0),
        };
    }

    public string Name => "Webgpu.Render";

    /// <summary>
    /// Exposes this module as the scene's <see cref="IRenderResources"/> and
    /// registers render's own node types (this domain's, not the framework's).
    /// </summary>
    public void Configure(IServiceCollection services)
    {
        services.AddSingleton<IRenderResources>(this);
        services
            .AddRenderComponentsNodeTypes()
            .AddUiComponentsNodeTypes()
            .AddNodeType<Sprite2D>();
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window    = services.GetRequiredService<IWindow>();
        var ecs       = services.GetRequiredService<IEcs>();
        var logger    = services.GetService<INativeLogger>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var world     = services.GetService<KernelEngine.Framework.World>();

        var win = ((INativeWindow)window).Native;
        var rt  = ((INativeRuntime)runtime).Native;
        var ec  = ((INativeEcs)ecs).Native;
        var lg  = logger != null ? logger.Native : null;
        var sc  = ((INativeScheduler)scheduler).Native;
        var wd  = world != null ? ((KernelEngine.Framework.INativeWorld)world).Native : null;

        ke_error* err = null;

        var dp = new ke_gpu_device_webgpu_params { window = win, enable_validation = 1, scheduler = sc };
        _device = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, &err);
        if (_device.@ref == null)
            throw Fail("webgpu device create failed", err);

        var config = services.GetService<IConfiguration>();
        var cp = new ke_render_cluster_params
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
            _module = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_create(rt, ec, _device.@ref, wd, 1, lg, ar, &cp, &fp, (sbyte*)sd, &err);
        if (_module.@ref == null)
            throw Fail("render module create failed", err);

        _core = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_core(_module.@ref);
        _renderService = RenderService.Borrow(_core);
        var clearColor = _clearColorOverride ?? ResolveClearColor(config);
        _renderService.SetClearColor(clearColor.X, clearColor.Y, clearColor.Z, clearColor.W);

    }

    /// <summary>
    /// Reads <c>[render] clear_color_r/g/b/a</c> from config. Split into four scalar keys
    /// rather than one array key — the native TOML loader (ke_configuration_toml) skips
    /// arrays, so a game wanting a config-driven clear color authors this shape.
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
    /// Uploads an interleaved mesh (position + normal vertices, 16-bit indices)
    /// to GPU buffers owned by the render core, returning a handle a
    /// <see cref="MeshComponent"/> references. Valid only after the module is
    /// loaded. Throws on failure — a bad upload is never swallowed.
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
    /// The render-core pointer, untyped. Used only by native calls that cross
    /// into another plugin (e.g. the framework's asset-resolver cached-load);
    /// never exposed to game code.
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
                u0 = g.U0, v0 = g.V0, u1 = g.U1, v1 = g.V1,
                bearing_x = g.BearingX, bearing_y = g.BearingY,
                width = g.Width, height = g.Height,
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

    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_module.@ref != null && _module.destroy != null)
            _module.destroy(_module.@ref);
        if (_device.@ref != null && _device.destroy != null)
            _device.destroy(_device.@ref);
    }
}
