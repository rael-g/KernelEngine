using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Logger;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Window;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device
/// from the window and installs the render path (ke_render_module) which
/// registers begin/clear/end as KE_PHASE_RENDER systems on the runtime. The host
/// just ticks the runtime — no render calls in the loop.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources
{
    private ke_gpu_device_handle _device;
    private ke_render_module_handle _module;
    private ke_render_core* _core;
    private readonly System.Numerics.Vector4 _clearColor;
    private readonly ke_render_cluster_params _clusterParams;
    private readonly ke_render_feature_params _featureParams;

    /// <param name="clearColor">Background color the default passes clear to (RGBA).</param>
    /// <param name="clusterGridX">Clustered-forward screen-tile columns; 0 = engine default (32).</param>
    /// <param name="clusterGridY">Clustered-forward screen-tile rows; 0 = engine default (18).</param>
    /// <param name="clusterGridZ">Clustered-forward depth slices; 0 = engine default (24).</param>
    /// <param name="maxLightsPerCluster">Per-froxel light-index-list cap; 0 = engine default (256). Raise this for scenes denser than the default sweet spot.</param>
    /// <param name="enableShadows">When false, no shadow pass and no shadow map render target exist — a game without shadows carries zero shadow-pass footprint. Default true (matches prior behavior).</param>
    /// <param name="enableIbl">When false, materials sample a forced-black environment regardless of any skybox (no ambient/reflection contribution). Skybox rendering itself is unaffected. Default true (matches prior behavior).</param>
    public WebgpuRenderModule(System.Numerics.Vector4 clearColor = default,
        uint clusterGridX = 0, uint clusterGridY = 0, uint clusterGridZ = 0, uint maxLightsPerCluster = 0,
        bool enableShadows = true, bool enableIbl = true)
    {
        _clearColor = clearColor == default ? new(0.10f, 0.15f, 0.30f, 1.0f) : clearColor;
        _clusterParams = new ke_render_cluster_params
        {
            grid_x = clusterGridX,
            grid_y = clusterGridY,
            grid_z = clusterGridZ,
            max_lights_per_cluster = maxLightsPerCluster,
        };
        _featureParams = new ke_render_feature_params
        {
            enable_shadows = (byte)(enableShadows ? 1 : 0),
            enable_ibl = (byte)(enableIbl ? 1 : 0),
        };
    }

    public string Name => "Webgpu.Render";

    /// <summary>Exposes this module as the scene's <see cref="IRenderResources"/>.</summary>
    public void Configure(IServiceCollection services)
        => services.AddSingleton<IRenderResources>(this);

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window = services.GetRequiredService<IWindow>();
        var ecs    = services.GetRequiredService<IEcs>();
        var logger = services.GetService<INativeLogger>();

        var win = ((INativeWindow)window).Native;
        var rt  = ((INativeRuntime)runtime).Native;
        var ec  = ((INativeEcs)ecs).Native;
        var lg  = logger != null ? logger.Native : null;

        ke_error* err = null;

        var dp = new ke_gpu_device_webgpu_params { window = win, enable_validation = 1 };
        _device = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, &err);
        if (_device.@ref == null)
            throw Fail("webgpu device create failed", err);

        var cp = _clusterParams;
        var fp = _featureParams;
        _module = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_create(rt, ec, _device.@ref, 1, lg, &cp, &fp, &err);
        if (_module.@ref == null)
            throw Fail("render module create failed", err);

        _core = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_core(_module.@ref);
        _core->set_clear_color(_core, _clearColor.X, _clearColor.Y, _clearColor.Z, _clearColor.W);
    }

    /// <summary>
    /// Uploads an interleaved mesh (position + normal vertices, 16-bit indices)
    /// to GPU buffers owned by the render core, returning a handle a
    /// <see cref="MeshComponent"/> references. Valid only after the module is
    /// loaded. Throws on failure — a bad upload is never swallowed.
    /// </summary>
    public MeshHandle UploadMesh(ReadOnlySpan<MeshVertex> vertices, ReadOnlySpan<ushort> indices)
    {
        if (_core == null)
            throw new InvalidOperationException("UploadMesh called before the render module was loaded");

        ke_error* err = null;
        ke_mesh_handle h;
        fixed (MeshVertex* v = vertices)
        fixed (ushort* i = indices)
        {
            h = _core->upload_mesh(_core, v, (nuint)(vertices.Length * sizeof(MeshVertex)),
                                   i, (uint)indices.Length, &err);
        }
        if (h.idx == uint.MaxValue)
            throw Fail("upload_mesh failed", err);
        return new MeshHandle(h.idx);
    }

    /// <inheritdoc/>
    public TextureHandle UploadTexture(uint width, uint height, ReadOnlySpan<byte> rgba)
    {
        if (_core == null)
            throw new InvalidOperationException("UploadTexture called before the render module was loaded");

        ke_error* err = null;
        ke_texture_handle h;
        fixed (byte* p = rgba)
            h = _core->upload_texture(_core, width, height, p, &err);
        if (h.idx == uint.MaxValue)
            throw Fail("upload_texture failed", err);
        return new TextureHandle(h.idx);
    }

    /// <inheritdoc/>
    public TextureHandle UploadCubemap(uint faceSize, ReadOnlySpan<byte> faces)
    {
        if (_core == null)
            throw new InvalidOperationException("UploadCubemap called before the render module was loaded");

        ke_error* err = null;
        ke_texture_handle h;
        fixed (byte* p = faces)
            h = _core->upload_cubemap(_core, faceSize, p, &err);
        if (h.idx == uint.MaxValue)
            throw Fail("upload_cubemap failed", err);
        return new TextureHandle(h.idx);
    }

    /// <inheritdoc/>
    public MaterialHandle CreateMaterial(System.Numerics.Vector4 baseColor, float metallic = 0f, float roughness = 0.5f,
                                         TextureHandle albedo = default, TextureHandle? normalMap = null,
                                         AlphaMode alphaMode = AlphaMode.Opaque, float alphaCutoff = 0.5f)
    {
        if (_core == null)
            throw new InvalidOperationException("CreateMaterial called before the render module was loaded");

        ke_error* err = null;
        ke_material_handle h;
        var albedoH = new ke_texture_handle { idx = albedo.Value };
        var normalH = new ke_texture_handle { idx = normalMap?.Value ?? uint.MaxValue };
        h = _core->create_material(_core, &baseColor.X, metallic, roughness, albedoH, normalH,
                                    (ke_alpha_mode)(int)alphaMode, alphaCutoff, &err);
        if (h.idx == uint.MaxValue)
            throw Fail("create_material failed", err);
        return new MaterialHandle(h.idx);
    }

    /// <inheritdoc/>
    public void UiQuad(TextureHandle texture, float dstX, float dstY, float dstW, float dstH,
                       float u0, float v0, float u1, float v1, System.Numerics.Vector4 premultipliedColor)
    {
        if (_module.@ref == null)
            throw new InvalidOperationException("UiQuad called before the render module was loaded");

        var texH = new ke_texture_handle { idx = texture.Value };
        KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_ui_quad(_module.@ref, texH, dstX, dstY, dstW, dstH, u0, v0, u1, v1,
                       premultipliedColor.X, premultipliedColor.Y, premultipliedColor.Z, premultipliedColor.W);
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
