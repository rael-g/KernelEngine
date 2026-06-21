using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Common;
using KernelEngine.Runtime;

namespace KernelEngine.Render;

/// <summary>
/// Hardware-accelerated renderer. Takes ownership of a <c>ke_render*</c> created by a service factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// All methods throw <see cref="KernelError"/> on failure.
/// </summary>
public sealed unsafe class Renderer : IRenderer, INativeRenderer
{
    private ke_render* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_render*, void> _destroy;

    ke_render* INativeRenderer.Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>
    /// Wraps an owner <c>ke_render_handle</c> without triggering backend initialization.
    /// Call <see cref="Initialize"/> on the thread that should become the bgfx API thread.
    /// </summary>
    public Renderer(ke_render_handle handle)
    {
        _native = handle.@ref;
        _destroy = handle.destroy;
    }

    /// <summary>
    /// Returns the renderer's active render graph — the one whose passes execute on every
    /// <see cref="SubmitPacket"/>. Add new <see cref="RenderPass"/>es to plug techniques
    /// (FXAA, debug overlays, custom compute) into the chain without forking the renderer.
    /// Returns <c>null</c> when the backend was constructed without a default graph.
    /// </summary>
    [RequiresThread("ke.render")]
    public RenderGraph? GetRenderGraph()
    {
        KernelThread.AssertCurrent("ke.render");
        if (_native->get_render_graph == null) return null;
        var g = _native->get_render_graph(_native);
        return g != null ? new RenderGraph(g) : null;
    }

    /// <summary>
    /// Calls <c>on_initialize</c> (bgfx::init). Must be called on the same thread that will
    /// subsequently call <see cref="Frame"/>. Typically invoked by the framework on the sim thread.
    /// </summary>
    [RequiresThread("ke.render")]
    public void Initialize()
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->on_initialize(_native, &err), err, "on_initialize");
    }

    /// <summary>Advances to the next frame and presents the current one. Call once per loop iteration.</summary>
    [RequiresThread("ke.render")]
    public void Frame()
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->frame(_native, &err), err, "frame");
    }

    /// <summary>Submits a pre-recorded frame packet to the hardware. Runs strictly on the render thread.</summary>
    [RequiresThread("ke.render")]
    public void SubmitPacket(IFramePacket packet)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->submit_packet(_native, ((FramePacket)packet).NativePointer, &err), err, "submit_packet");
    }

    /// <summary>Sets the background clear color for the next frame.</summary>
    [RequiresThread("ke.render")]
    public void ClearColor(float r, float g, float b, float a)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->clear_color(_native, r, g, b, a, &err), err, "clear_color");
    }

    /// <summary>Sets the background clear color for the next frame.</summary>
    [RequiresThread("ke.render")]
    public void ClearColor(Vector4 color)
    {
        KernelThread.AssertCurrent("ke.render");
        ClearColor(color.X, color.Y, color.Z, color.W);
    }

    /// <summary>Toggles orthographic projection mode.</summary>
    [RequiresThread("ke.render")]
    public void SetOrthographic(bool enabled)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_orthographic(_native, (byte)(enabled ? 1 : 0), &err), err, "set_orthographic");
    }

    /// <summary>Sets the view and projection matrices for the active view. Call once per frame before draw calls.</summary>
    [RequiresThread("ke.render")]
    public void SetViewTransform(Matrix4x4 view, Matrix4x4 proj)
    {
        KernelThread.AssertCurrent("ke.render");
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref view);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref proj);
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_view_transform(_native, &v, &p, &err), err, "set_view_transform");
    }

    /// <inheritdoc/>
    [RequiresThread("ke.render")]
    public NdcConvention GetNdcConvention()
    {
        KernelThread.AssertCurrent("ke.render");
        var c = _native->get_ndc_convention(_native);
        return new NdcConvention(c.z_zero_to_one != 0, c.y_flip != 0, c.left_handed != 0);
    }

    /// <summary>Uploads geometry to the GPU and returns a stable mesh handle.</summary>
    [RequiresThread("ke.render")]
    public MeshHandle CreateMesh(Vertex[] vertices, ushort[] indices)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (Vertex* vp = vertices)
        fixed (ushort* ip = indices)
        {
            ke_error* err = null;
            var h = _native->create_mesh(_native, (ke_vertex*)vp, (uint)vertices.Length, ip, (uint)indices.Length, &err);
            if (h.idx == uint.MaxValue) throw KernelError.FromNative(err, "create_mesh");
            return new MeshHandle(h.idx);
        }
    }

    /// <summary>Releases GPU resources for a mesh handle.</summary>
    [RequiresThread("ke.render")]
    public void DestroyMesh(MeshHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid mesh handle", nameof(handle));
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->destroy_mesh(_native, new ke_mesh_handle { idx = handle.Value }, &err), err, "destroy_mesh");
    }

    /// <summary>Uploads raw RGBA8 pixel data to the GPU and returns a stable texture handle.</summary>
    [RequiresThread("ke.render")]
    public TextureHandle CreateTexture(uint width, uint height, byte[] pixels)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (byte* px = pixels)
        {
            ke_error* err = null;
            var h = _native->create_texture_rgba(_native, width, height, px, &err);
            if (h.idx == uint.MaxValue) throw KernelError.FromNative(err, "create_texture_rgba");
            return new TextureHandle(h.idx);
        }
    }

    /// <summary>Releases GPU resources for a texture handle.</summary>
    [RequiresThread("ke.render")]
    public void DestroyTexture(TextureHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid texture handle", nameof(handle));
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->destroy_texture(_native, new ke_texture_handle { idx = handle.Value }, &err), err, "destroy_texture");
    }

    /// <summary>Creates a material from properties, returning a stable handle.</summary>
    [RequiresThread("ke.render")]
    public MaterialHandle CreateMaterial(float r, float g, float b, float a, TextureHandle textureHandle = default,
                           float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default)
    {
        KernelThread.AssertCurrent("ke.render");
        if (textureHandle == default) textureHandle = TextureHandle.White;
        if (normalMapHandle == default) normalMapHandle = TextureHandle.None;

        var mat = new ke_material { r = r, g = g, b = b, a = a,
                                    albedo = new ke_texture_handle { idx = textureHandle.Value },
                                    metallic = metallic, roughness = roughness,
                                    normal_map = new ke_texture_handle { idx = normalMapHandle.Value } };
        ke_error* err = null;
        var h = _native->create_material(_native, &mat, &err);
        if (h.idx == uint.MaxValue) throw KernelError.FromNative(err, "create_material");
        return new MaterialHandle(h.idx);
    }

    /// <inheritdoc cref="CreateMaterial(float,float,float,float,TextureHandle,float,float,TextureHandle)"/>
    [RequiresThread("ke.render")]
    public MaterialHandle CreateMaterial(Vector4 color, TextureHandle textureHandle = default,
                           float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default)
    {
        KernelThread.AssertCurrent("ke.render");
        return CreateMaterial(color.X, color.Y, color.Z, color.W, textureHandle, metallic, roughness, normalMapHandle);
    }

    /// <summary>Releases a material handle.</summary>
    [RequiresThread("ke.render")]
    public void DestroyMaterial(MaterialHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid material handle", nameof(handle));
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->destroy_material(_native, new ke_material_handle { idx = handle.Value }, &err), err, "destroy_material");
    }

    /// <summary>Sets the active directional light for the current frame.</summary>
    [RequiresThread("ke.render")]
    public void SetDirectionalLight(float dirX, float dirY, float dirZ,
                                    float r, float g, float b, float intensity)
    {
        KernelThread.AssertCurrent("ke.render");
        var light = new ke_directional_light
        {
            dir_x = dirX, dir_y = dirY, dir_z = dirZ,
            r = r, g = g, b = b, intensity = intensity,
        };
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_directional_light(_native, &light, &err), err, "set_directional_light");
    }

    /// <summary>Sets the ambient light color for the current frame.</summary>
    [RequiresThread("ke.render")]
    public void SetAmbientLight(float r, float g, float b)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_ambient_light(_native, r, g, b, &err), err, "set_ambient_light");
    }

    /// <summary>Sets the camera world-space position used for PBR specular calculations. Call once per frame.</summary>
    [RequiresThread("ke.render")]
    public void SetCameraPos(float x, float y, float z)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_camera_pos(_native, x, y, z, &err), err, "set_camera_pos");
    }

    /// <summary>Uploads up to 8 point lights for the current frame. Replaces any previously set point lights.</summary>
    [RequiresThread("ke.render")]
    public void SetPointLights(ReadOnlySpan<ke_point_light> lights)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (ke_point_light* p = lights)
        {
            ke_error* err = null;
            KernelError.ThrowIfFailed(_native->set_point_lights(_native, p, (uint)lights.Length, &err), err, "set_point_lights");
        }
    }

    /// <summary>Uploads up to 8 spot lights for the current frame. Replaces any previously set spot lights.</summary>
    [RequiresThread("ke.render")]
    public void SetSpotLights(ReadOnlySpan<ke_spot_light> lights)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (ke_spot_light* p = lights)
        {
            ke_error* err = null;
            KernelError.ThrowIfFailed(_native->set_spot_lights(_native, p, (uint)lights.Length, &err), err, "set_spot_lights");
        }
    }

    /// <summary>
    /// Enables or disables screen-space ambient occlusion (SSAO).
    /// </summary>
    [RequiresThread("ke.render")]
    public void SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_ssao(_native, (byte)(enabled ? 1 : 0), radius, bias, strength, &err), err, "set_ssao");
    }

    /// <summary>
    /// Configures the grid dimensions and light density limits for the Clustered Forward Shading pipeline.
    /// </summary>
    [RequiresThread("ke.render")]
    public void SetClusterConfig(uint gridX, uint gridY, uint gridZ, uint maxLightsPerCluster, uint maxTotalLights)
    {
        KernelThread.AssertCurrent("ke.render");
        var config = new ke_cluster_config
        {
            grid_x = gridX,
            grid_y = gridY,
            grid_z = gridZ,
            max_lights_per_cluster = maxLightsPerCluster,
            max_total_lights = maxTotalLights,
        };
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_cluster_config(_native, &config, &err), err, "set_cluster_config");
    }

    /// <summary>
    /// Uploads 6 RGBA8 face images into a GPU cubemap and returns a stable handle.
    /// </summary>
    [RequiresThread("ke.render")]
    public TextureHandle CreateCubemap(uint faceSize, byte[] data)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (byte* px = data)
        {
            ke_error* err = null;
            var h = _native->create_cubemap_rgba(_native, faceSize, px, &err);
            if (h.idx == uint.MaxValue) throw KernelError.FromNative(err, "create_cubemap_rgba");
            return new TextureHandle(h.idx);
        }
    }

    /// <summary>Submits the skybox draw call for the given cubemap handle.</summary>
    [RequiresThread("ke.render")]
    public void SubmitSkybox(TextureHandle cubemapHandle)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->submit_skybox(_native, new ke_texture_handle { idx = cubemapHandle.Value }, &err), err, "submit_skybox");
    }

    /// <summary>Submits a draw call for a mesh using a material and world transform.</summary>
    [RequiresThread("ke.render")]
    public void SubmitMesh(MeshHandle meshHandle, MaterialHandle materialHandle, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.render");
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->submit_mesh(_native, new ke_mesh_handle { idx = meshHandle.Value }, new ke_material_handle { idx = materialHandle.Value }, &mat, &err), err, "submit_mesh");
    }

    /// <summary>Allocates a GPU shadow map of the given dimensions. Returns a stable handle.</summary>
    [RequiresThread("ke.render")]
    public ShadowMapHandle CreateShadowMap(uint width, uint height)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        var h = _native->create_shadow_map(_native, width, height, &err);
        if (h.idx == uint.MaxValue) throw KernelError.FromNative(err, "create_shadow_map");
        return new ShadowMapHandle(h.idx);
    }

    /// <summary>Releases a shadow map and its GPU resources.</summary>
    [RequiresThread("ke.render")]
    public void DestroyShadowMap(ShadowMapHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->destroy_shadow_map(_native, new ke_shadow_map_handle { idx = handle.Value }, &err), err, "destroy_shadow_map");
    }

    /// <summary>
    /// Begins the shadow depth pass for the given shadow map. Call once per frame before
    /// any <see cref="SubmitMeshShadow"/> calls.
    /// </summary>
    [RequiresThread("ke.render")]
    public void BeginShadowPass(ShadowMapHandle shadowMapHandle, Matrix4x4 lightView, Matrix4x4 lightProj)
    {
        KernelThread.AssertCurrent("ke.render");
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref lightView);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref lightProj);
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->begin_shadow_pass(_native, new ke_shadow_map_handle { idx = shadowMapHandle.Value }, &v, &p, &err), err, "begin_shadow_pass");
    }

    /// <summary>Submits a mesh to the shadow depth pass. Call between Begin/EndShadowPass.</summary>
    [RequiresThread("ke.render")]
    public void SubmitMeshShadow(MeshHandle meshHandle, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.render");
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->submit_mesh_shadow(_native, new ke_mesh_handle { idx = meshHandle.Value }, &mat, &err), err, "submit_mesh_shadow");
    }

    /// <summary>Ends the shadow depth pass.</summary>
    [RequiresThread("ke.render")]
    public void EndShadowPass()
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->end_shadow_pass(_native, &err), err, "end_shadow_pass");
    }

    /// <summary>Overrides which shadow map is bound during the current frame's Tree pass.</summary>
    [RequiresThread("ke.render")]
    public void SetShadowMap(ShadowMapHandle shadowMapHandle)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_shadow_map(_native, new ke_shadow_map_handle { idx = shadowMapHandle.Value }, &err), err, "set_shadow_map");
    }

    /// <summary>
    /// Enables HDR tonemapping. When enabled, ACES tonemapping and gamma correction are applied before display.
    /// </summary>
    [RequiresThread("ke.render")]
    public void SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_tonemapping(_native, (byte)(enabled ? 1 : 0), exposure, gamma, &err), err, "set_tonemapping");
    }

    /// <summary>
    /// Enables bloom post-processing. Requires <see cref="SetTonemapping"/> to be active.
    /// </summary>
    [RequiresThread("ke.render")]
    public void SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_error* err = null;
        KernelError.ThrowIfFailed(_native->set_bloom(_native, (byte)(enabled ? 1 : 0), threshold, intensity, &err), err, "set_bloom");
    }

    /// <inheritdoc/>
    public string? GetLastFatalError()
    {
        KernelThread.AssertCurrent("ke.render");
        var ptr = _native->get_last_fatal_error(_native);
        return ptr != null ? Marshal.PtrToStringAnsi((nint)ptr) : null;
    }

    /// <inheritdoc/>
    [RequiresThread("ke.render")]
    public void Dispose()
    {
        if (_native == null) return; // idempotent — ke.render disposes first; DI container may call again from ke.main
        KernelThread.AssertCurrent("ke.render");
        _native->on_shutdown(_native, null);
        if (_destroy != null) _destroy(_native);
        _native = null;
    }
}
