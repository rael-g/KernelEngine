
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
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device and a render
/// target presenting into the window, and composes the renderer on the runtime: the render
/// service, the camera, the scene resolve, the frame, the shadow, cluster, gbuffer, deferred
/// lighting, skybox, forward, tonemap and ui passes, and the label resolve. The host just ticks
/// the runtime; no render calls in the loop.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources, INativeRenderResources
{
    private ke_gpu_device_handle _device;
    private ke_gpu_render_target_handle _target;
    private KernelEngine.Render.Native.ke_render_resource_binder_handle _binder;
    private KernelEngine.Render.Native.ke_render_service_handle _service;
    private KernelEngine.View.Native.ke_view_space_handle _viewSpace;
    private KernelEngine.Render.Native.ke_render_camera_handle _camera;
    private ke_render_scene_resolve_handle _scene;
    private ke_render_frame_handle _frame;
    private ke_render_shadow_handle _shadow;
    private ke_render_cluster_handle _cluster;
    private ke_render_gbuffer_handle _gbuffer;
    private ke_render_deferred_lighting_handle _deferred;
    private ke_render_skybox_handle _skybox;
    private ke_render_forward_handle _forward;
    private ke_render_tonemap_handle _tonemap;
    private ke_render_ui_handle _ui;
    private ke_render_label_resolve_handle _labels;
    private ke_render_service* _core;
    private RenderService? _renderService;
    private readonly string _shaderDir;
    private readonly System.Numerics.Vector4? _clearColorOverride;
    private readonly uint _clusterGridXOverride, _clusterGridYOverride, _clusterGridZOverride, _maxLightsPerClusterOverride;
    private readonly bool _debugLabelsOverride;
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
    }

    /// <summary>
    /// Creates the device, the window target and the renderer. The window target presents
    /// with vertical sync unless <c>[runtime.renderer] vsync</c> is false in
    /// <see cref="IConfiguration"/>, in which case frames are shown at once.
    /// </summary>
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window = services.GetRequiredService<IWindow>();
        var ecs = services.GetRequiredService<INativeEcs>();
        var scheduler = services.GetRequiredService<IScheduler>();
        var world = services.GetService<KernelEngine.Framework.World>();

        var win = ((INativeWindow)window).Native;
        var rt = ((INativeRuntime)runtime).Native;
        var ec = ecs.Native;
        var sc = ((INativeScheduler)scheduler).Native;
        var wd = world != null ? ((KernelEngine.Framework.INativeWorld)world).Native : null;

        if (services.GetService<ILogger>() is { } logger)
            RouteLogs(logger);

        var config = services.GetService<IConfiguration>();
        var debugLabels = _debugLabelsOverride || (config?.GetBool("render", "debug_labels", false) ?? false);
        var dp = new ke_gpu_device_webgpu_params { enable_validation = true, scheduler = sc, debug_labels = debugLabels };
        fixed (ke_gpu_device_handle* made = &_device)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, made), "webgpu device create");

        var vsync = config?.GetBool("runtime.renderer", "vsync", true) ?? true;
        var tp = new ke_gpu_render_target_webgpu_window_params
        {
            device = _device.@ref,
            window = win,
            present_mode = vsync ? ke_gpu_present_mode.KE_GPU_PRESENT_MODE_FIFO : ke_gpu_present_mode.KE_GPU_PRESENT_MODE_IMMEDIATE,
        };
        fixed (ke_gpu_render_target_handle* made = &_target)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_render_target_webgpu_window_create(&tp, made), "webgpu window render target create");

        var ar = services.GetService<KernelEngine.Framework.NativeAssetResolver>() is { } resolver
            ? (KernelEngine.Asset.Native.ke_asset_resolver*)((KernelEngine.Framework.INativeAssetResolver)resolver).Native
            : null;
        Compose(rt, ec, wd, ar, config);

        _renderService = RenderService.Borrow(_core);
        var clearColor = _clearColorOverride ?? ResolveClearColor(config);
        _renderService.SetClearColor(clearColor.X, clearColor.Y, clearColor.Z, clearColor.W);

    }

    /// <summary>
    /// Sends the log of every native library this module composes to <paramref name="logger"/>.
    /// </summary>
    private static void RouteLogs(ILogger logger)
    {
        var callback = LogCallbackNative.Pointer;
        var ctx = LogCallbackNative.Pin(logger.Log);
        KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_binder_grouped_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_service_set_log_callback(callback, ctx);
        KernelEngine.View.Native.NativeMethods.view_space_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_camera_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_scene_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_frame_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_shadow_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_cluster_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_gbuffer_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_deferred_lighting_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_skybox_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_forward_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_tonemap_set_log_callback(callback, ctx);
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_ui_set_log_callback(callback, ctx);
    }

    /// <summary>
    /// Creates every piece of the renderer on the device and the window target and wires their
    /// component ids together, then registers render's scene components into the world when there
    /// is one. Throws <see cref="InvalidOperationException"/> naming the first piece that fails.
    /// </summary>
    private void Compose(KernelEngine.Runtime.Native.ke_runtime* rt, KernelEngine.Ecs.Native.ke_ecs* ec,
        KernelEngine.Framework.Native.ke_world* wd,
        KernelEngine.Asset.Native.ke_asset_resolver* ar, IConfiguration? config)
    {
        var dev = _device.@ref;
        var shaderDirBytes = System.Text.Encoding.UTF8.GetBytes(_shaderDir + '\0');
        fixed (byte* sd = shaderDirBytes)
        {
            var bp = new ke_render_resource_binder_grouped_params { device = dev, shader_dir = (sbyte*)sd };
            fixed (KernelEngine.Render.Native.ke_render_resource_binder_handle* made = &_binder)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_resource_binder_grouped_create(&bp, made), "resource binder create");
            var sp = new ke_render_service_params { device = dev, target = _target.@ref, ecs = ec, shader_dir = (sbyte*)sd, binder = _binder.@ref };
            fixed (KernelEngine.Render.Native.ke_render_service_handle* made = &_service)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_service_create(&sp, made), "render service create");
        }
        var core = _service.@ref;
        _core = core;

        var ndc = dev->get_ndc_convention(dev);
        KernelEngine.View.Native.ke_view_space_handle viewSpace;
        KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.View.Native.NativeMethods.view_space_rh_create(&viewSpace), "ke_view_space_rh_create");
        _viewSpace = viewSpace;
        fixed (KernelEngine.Render.Native.ke_render_camera_handle* made = &_camera)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_camera_create(_viewSpace.@ref, &ndc, made), "camera create");

        var scp = new ke_render_scene_resolve_params { runtime = rt, ecs = ec, service = core, resolver = ar };
        fixed (ke_render_scene_resolve_handle* made = &_scene)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_scene_resolve_create(&scp, made), "scene resolve create");
        var ids = *_scene.@ref->component_ids(_scene.@ref);

        var frp = new ke_render_frame_params
        {
            runtime = rt,
            ecs = ec,
            service = core,
            camera = _camera.@ref,
            camera_cid = ids.camera,
            world_transform_cid = ids.world_transform,
            directional_light_cid = ids.directional_light,
            ambient_light_cid = ids.ambient_light,
        };
        fixed (ke_render_frame_handle* made = &_frame)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_frame_create(&frp, made), "frame create");
        var frameCid = _frame.@ref->frame_cid(_frame.@ref);

        fixed (byte* shadowName = "shadow\0"u8)
        fixed (byte* clustersName = "clusters\0"u8)
        fixed (byte* gbufferName = "gbuffer\0"u8)
        {
            var shadowGroup = _enableShadows ? (sbyte*)shadowName : null;
            if (_enableShadows)
            {
                var shp = new ke_render_shadow_params
                {
                    runtime = rt,
                    service = core,
                    device = dev,
                    view_space = _viewSpace.@ref,
                    ndc = ndc,
                    mesh_cid = ids.mesh,
                    world_transform_cid = ids.world_transform,
                    light_cid = ids.directional_light,
                    frame_cid = frameCid,
                    output = shadowGroup,
                };
                fixed (ke_render_shadow_handle* made = &_shadow)
                    KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_shadow_create(&shp, made), "shadow pass create");
            }

            var clp = new ke_render_cluster_params
            {
                runtime = rt,
                service = core,
                device = dev,
                view_space = _viewSpace.@ref,
                camera = _camera.@ref,
                point_light_cid = ids.point_light,
                spot_light_cid = ids.spot_light,
                world_transform_cid = ids.world_transform,
                camera_cid = ids.camera,
                frame_cid = frameCid,
                output = (sbyte*)clustersName,
                grid_x = _clusterGridXOverride != 0 ? _clusterGridXOverride : (uint)(config?.GetInt("render", "cluster_grid_x", 0) ?? 0),
                grid_y = _clusterGridYOverride != 0 ? _clusterGridYOverride : (uint)(config?.GetInt("render", "cluster_grid_y", 0) ?? 0),
                grid_z = _clusterGridZOverride != 0 ? _clusterGridZOverride : (uint)(config?.GetInt("render", "cluster_grid_z", 0) ?? 0),
                max_lights_per_cluster = _maxLightsPerClusterOverride != 0
                    ? _maxLightsPerClusterOverride
                    : (uint)(config?.GetInt("render", "max_lights_per_cluster", 0) ?? 0),
            };
            fixed (ke_render_cluster_handle* made = &_cluster)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_cluster_create(&clp, made), "cluster pass create");

            var gbp = new ke_render_gbuffer_params
            {
                runtime = rt,
                service = core,
                device = dev,
                mesh_cid = ids.mesh,
                world_transform_cid = ids.world_transform,
                camera_cid = ids.camera,
                frame_cid = frameCid,
                output = (sbyte*)gbufferName,
            };
            fixed (ke_render_gbuffer_handle* made = &_gbuffer)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_gbuffer_create(&gbp, made), "gbuffer pass create");

            var dlp = new ke_render_deferred_lighting_params
            {
                runtime = rt,
                service = core,
                device = dev,
                ibl_enabled = _enableIbl,
                camera_cid = ids.camera,
                world_transform_cid = ids.world_transform,
                skybox_cid = ids.skybox,
                frame_cid = frameCid,
                gbuffer = (sbyte*)gbufferName,
                shadow = shadowGroup,
                clusters = (sbyte*)clustersName,
            };
            fixed (ke_render_deferred_lighting_handle* made = &_deferred)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_deferred_lighting_create(&dlp, made), "deferred lighting pass create");

            var skp = new ke_render_skybox_params
            {
                runtime = rt,
                service = core,
                device = dev,
                camera = _camera.@ref,
                camera_cid = ids.camera,
                world_transform_cid = ids.world_transform,
                skybox_cid = ids.skybox,
                frame_cid = frameCid,
            };
            fixed (ke_render_skybox_handle* made = &_skybox)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_skybox_create(&skp, made), "skybox pass create");

            var fwp = new ke_render_forward_params
            {
                runtime = rt,
                service = core,
                device = dev,
                ibl_enabled = _enableIbl,
                mesh_cid = ids.mesh,
                world_transform_cid = ids.world_transform,
                camera_cid = ids.camera,
                skybox_cid = ids.skybox,
                frame_cid = frameCid,
                shadow = shadowGroup,
                clusters = (sbyte*)clustersName,
            };
            fixed (ke_render_forward_handle* made = &_forward)
                KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_forward_create(&fwp, made), "forward pass create");
        }

        var tmp = new ke_render_tonemap_params { runtime = rt, service = core, device = dev, frame_cid = frameCid };
        fixed (ke_render_tonemap_handle* made = &_tonemap)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_tonemap_create(&tmp, made), "tonemap pass create");

        var uip = new ke_render_ui_params { runtime = rt, ecs = ec, service = core, device = dev, ndc = ndc, frame_cid = frameCid };
        fixed (ke_render_ui_handle* made = &_ui)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_ui_create(&uip, made), "ui pass create");

        var lrp = new ke_render_label_resolve_params { runtime = rt, service = core, ui = _ui.@ref, resolver = ar, label_cid = ids.label };
        fixed (ke_render_label_resolve_handle* made = &_labels)
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Render.Webgpu.Native.NativeMethods.render_label_resolve_create(&lrp, made), "label resolve create");

        if (wd == null)
            return;
        var set = KernelEngine.Render.Webgpu.Native.NativeMethods.render_scene_components_create();
        try
        {
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
        if (_ui.@ref == null)
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
        KernelEngine.Render.Native.ke_ui_font_handle h;
        fixed (byte* k = keyBytes)
            KernelEngine.NativeResults.ThrowIfFailed(_ui.@ref->load_font(_ui.@ref, (sbyte*)k, texH, native, (uint)glyphs.Length, lineHeight, ascent, &h), "load_font");
        return new FontHandle(h.bits);
    }

    /// <summary>
    /// Destroys the renderer's pieces in the reverse of their creation, then the render target,
    /// then the device, skipping any that was never created.
    /// </summary>
    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_labels.@ref != null) _labels.destroy(_labels.@ref);
        if (_ui.@ref != null) _ui.destroy(_ui.@ref);
        if (_tonemap.@ref != null) _tonemap.destroy(_tonemap.@ref);
        if (_forward.@ref != null) _forward.destroy(_forward.@ref);
        if (_skybox.@ref != null) _skybox.destroy(_skybox.@ref);
        if (_deferred.@ref != null) _deferred.destroy(_deferred.@ref);
        if (_gbuffer.@ref != null) _gbuffer.destroy(_gbuffer.@ref);
        if (_cluster.@ref != null) _cluster.destroy(_cluster.@ref);
        if (_shadow.@ref != null) _shadow.destroy(_shadow.@ref);
        if (_frame.@ref != null) _frame.destroy(_frame.@ref);
        if (_scene.@ref != null) _scene.destroy(_scene.@ref);
        if (_camera.@ref != null) _camera.destroy(_camera.@ref);
        if (_service.@ref != null) _service.destroy(_service.@ref);
        if (_binder.@ref != null) _binder.destroy(_binder.@ref);
        if (_viewSpace.@ref != null) _viewSpace.destroy(_viewSpace.@ref);
        if (_target.@ref != null && _target.destroy != null)
            _target.destroy(_target.@ref);
        if (_device.@ref != null && _device.destroy != null)
            _device.destroy(_device.@ref);
    }
}
