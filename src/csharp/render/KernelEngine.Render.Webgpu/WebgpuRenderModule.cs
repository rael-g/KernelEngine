using System.Runtime.InteropServices;
using KernelEngine.Common.Native;
using KernelEngine.Ecs;
using KernelEngine.Render.Webgpu.Native;
using KernelEngine.Runtime;
using KernelEngine.Window;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Render.Webgpu;

/// <summary>
/// Render v2 (webgpu) as an <see cref="IRuntimeModule"/>. Creates the GPU device
/// from the window and installs the render path (ke_render_module) which
/// registers begin/clear/end as KE_PHASE_RENDER systems on the runtime. The host
/// just ticks the runtime — no render calls in the loop. Coexists with
/// BgfxRenderModule as an alternate DI choice.
/// </summary>
public sealed unsafe class WebgpuRenderModule : IRuntimeModule, IRenderResources
{
    private ke_gpu_device_handle _device;
    private ke_render_module_handle _module;
    private ke_render_core* _core;
    private readonly System.Numerics.Vector4 _clearColor;

    /// <param name="clearColor">Background color the default passes clear to (RGBA).</param>
    public WebgpuRenderModule(System.Numerics.Vector4 clearColor = default)
        => _clearColor = clearColor == default ? new(0.10f, 0.15f, 0.30f, 1.0f) : clearColor;

    public string Name => "Webgpu.Render";

    /// <summary>Exposes this module as the scene's <see cref="IRenderResources"/>.</summary>
    public void Configure(IServiceCollection services)
        => services.AddSingleton<IRenderResources>(this);

    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var window = services.GetRequiredService<IWindow>();
        var ecs    = services.GetRequiredService<IEcs>();

        var win = ((INativeWindow)window).Native;
        var rt  = ((INativeRuntime)runtime).Native;
        var ec  = ((INativeEcs)ecs).Native;

        ke_error* err = null;

        var dp = new ke_gpu_device_webgpu_params { window = win, enable_validation = 1 };
        _device = KernelEngine.Render.Webgpu.Native.NativeMethods.gpu_device_webgpu_create(&dp, &err);
        if (_device.@ref == null)
            throw Fail("webgpu device create failed", err);

        _module = KernelEngine.Render.Webgpu.Native.NativeMethods.render_module_create(rt, ec, _device.@ref, 1, &err);
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
    public MaterialHandle CreateMaterial(System.Numerics.Vector4 baseColor, float metallic = 0f, float roughness = 0.5f, TextureHandle albedo = default)
    {
        if (_core == null)
            throw new InvalidOperationException("CreateMaterial called before the render module was loaded");

        ke_error* err = null;
        ke_material_handle h;
        var albedoH = new ke_texture_handle { idx = albedo.Value };
        h = _core->create_material(_core, &baseColor.X, metallic, roughness, albedoH, &err);
        if (h.idx == uint.MaxValue)
            throw Fail("create_material failed", err);
        return new MaterialHandle(h.idx);
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
