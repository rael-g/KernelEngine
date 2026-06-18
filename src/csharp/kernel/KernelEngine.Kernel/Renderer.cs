using System.Numerics;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Hardware-accelerated renderer. Takes ownership of a <c>ke_render*</c> created by a service factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// </summary>
public sealed unsafe class Renderer : IRenderer
{
    private ke_render* _native;
    private readonly delegate* unmanaged[Cdecl]<ke_render*, void> _destroy;

    public ke_render* Native
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
        if (Native->get_render_graph == null) return null;
        var g = Native->get_render_graph(Native);
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
        KernelException.ThrowIfFailed(_native->on_initialize(_native, null).ToManaged());
    }

    /// <summary>Advances to the next frame and presents the current one. Call once per loop iteration.</summary>
    [RequiresThread("ke.render")]
    public Result Frame()
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->frame(_native, null).Wrap();
    }

    /// <summary>
    /// Submits a pre-recorded frame packet to the hardware.
    /// Runs strictly on the render thread.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result SubmitPacket(IFramePacket packet)
    {
        KernelThread.AssertCurrent("ke.render");
        // Get the internal raw pointer from the FramePacket (needs internal access or helper)
        return _native->submit_packet(_native, ((FramePacket)packet).NativePointer, null).Wrap();
    }

    /// <summary>Sets the background clear color for the next frame.</summary>
    [RequiresThread("ke.render")]
    public Result ClearColor(float r, float g, float b, float a)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->clear_color(_native, r, g, b, a, null).Wrap();
    }

    /// <summary>Sets the background clear color for the next frame.</summary>
    [RequiresThread("ke.render")]
    public Result ClearColor(Vector4 color)
    {
        KernelThread.AssertCurrent("ke.render");
        return ClearColor(color.X, color.Y, color.Z, color.W);
    }

    /// <summary>Toggles orthographic projection mode.</summary>
    [RequiresThread("ke.render")]
    public Result SetOrthographic(bool enabled)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_orthographic(_native, (byte)(enabled ? 1 : 0), null).Wrap();
    }

    /// <summary>Sets the view and projection matrices for the active view. Call once per frame before draw calls.</summary>
    [RequiresThread("ke.render")]
    public Result SetViewTransform(Matrix4x4 view, Matrix4x4 proj)
    {
        KernelThread.AssertCurrent("ke.render");
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref view);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref proj);
        return _native->set_view_transform(_native, &v, &p, null).Wrap();
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
    public Result<MeshHandle> CreateMesh(Vertex[] vertices, ushort[] indices)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_mesh_handle handle;
        // Vertex layout matches ke_vertex exactly (validated by tests); reinterpret-cast the buffer.
        fixed (Vertex* vp = vertices)
        fixed (ushort* ip = indices)
        {
            var res = _native->create_mesh(_native, (ke_vertex*)vp, (uint)vertices.Length, ip, (uint)indices.Length, &handle, null);
            return res.Wrap(new MeshHandle(handle.idx));
        }
    }

    /// <summary>Releases GPU resources for a mesh handle.</summary>
    [RequiresThread("ke.render")]
    public Result DestroyMesh(MeshHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid mesh handle", nameof(handle));
        return _native->destroy_mesh(_native, new ke_mesh_handle { idx = handle.Value }, null).Wrap();
    }

    /// <summary>Uploads raw RGBA8 pixel data to the GPU and returns a stable texture handle.</summary>
    [RequiresThread("ke.render")]
    public Result<TextureHandle> CreateTexture(uint width, uint height, byte[] pixels)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_texture_handle handle;
        fixed (byte* px = pixels)
        {
            var res = _native->create_texture_rgba(_native, width, height, px, &handle, null);
            return res.Wrap(new TextureHandle(handle.idx));
        }
    }

    /// <summary>Releases GPU resources for a texture handle.</summary>
    [RequiresThread("ke.render")]
    public Result DestroyTexture(TextureHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid texture handle", nameof(handle));
        return _native->destroy_texture(_native, new ke_texture_handle { idx = handle.Value }, null).Wrap();
    }

    /// <summary>Creates a material from properties, returning a stable handle.</summary>
    [RequiresThread("ke.render")]
    public Result<MaterialHandle> CreateMaterial(float r, float g, float b, float a, TextureHandle textureHandle = default,
                               float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_material_handle handle;
        if (textureHandle == default) textureHandle = TextureHandle.White;
        if (normalMapHandle == default) normalMapHandle = TextureHandle.None;

        var mat = new ke_material { r = r, g = g, b = b, a = a, 
                                    albedo = new ke_texture_handle { idx = textureHandle.Value },
                                    metallic = metallic, roughness = roughness,
                                    normal_map = new ke_texture_handle { idx = normalMapHandle.Value } };
        var res = _native->create_material(_native, &mat, &handle, null);
        return res.Wrap(new MaterialHandle(handle.idx));
    }

    /// <inheritdoc cref="CreateMaterial(float,float,float,float,TextureHandle,float,float,TextureHandle)"/>
    [RequiresThread("ke.render")]
    public Result<MaterialHandle> CreateMaterial(Vector4 color, TextureHandle textureHandle = default,
                               float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default)
    {
        KernelThread.AssertCurrent("ke.render");
        return CreateMaterial(color.X, color.Y, color.Z, color.W, textureHandle, metallic, roughness, normalMapHandle);
    }

    /// <summary>Releases a material handle.</summary>
    [RequiresThread("ke.render")]
    public Result DestroyMaterial(MaterialHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        if (!handle.IsValid) throw new ArgumentException("Invalid material handle", nameof(handle));
        return _native->destroy_material(_native, new ke_material_handle { idx = handle.Value }, null).Wrap();
    }

    /// <summary>Sets the active directional light for the current frame.</summary>
    [RequiresThread("ke.render")]
    public Result SetDirectionalLight(float dirX, float dirY, float dirZ,
                                    float r, float g, float b, float intensity)
    {
        KernelThread.AssertCurrent("ke.render");
        var light = new ke_directional_light
        {
            dir_x = dirX, dir_y = dirY, dir_z = dirZ,
            r = r, g = g, b = b, intensity = intensity,
        };
        return _native->set_directional_light(_native, &light, null).Wrap();
    }

    /// <summary>Sets the ambient light color for the current frame.</summary>
    [RequiresThread("ke.render")]
    public Result SetAmbientLight(float r, float g, float b)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_ambient_light(_native, r, g, b, null).Wrap();
    }

    /// <summary>Sets the camera world-space position used for PBR specular calculations. Call once per frame.</summary>
    [RequiresThread("ke.render")]
    public Result SetCameraPos(float x, float y, float z)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_camera_pos(_native, x, y, z, null).Wrap();
    }

    /// <summary>Uploads up to 8 point lights for the current frame. Replaces any previously set point lights.</summary>
    [RequiresThread("ke.render")]
    public Result SetPointLights(ReadOnlySpan<ke_point_light> lights)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (ke_point_light* p = lights)
            return _native->set_point_lights(_native, p, (uint)lights.Length, null).Wrap();
    }

    /// <summary>Uploads up to 8 spot lights for the current frame. Replaces any previously set spot lights.</summary>
    [RequiresThread("ke.render")]
    public Result SetSpotLights(ReadOnlySpan<ke_spot_light> lights)
    {
        KernelThread.AssertCurrent("ke.render");
        fixed (ke_spot_light* p = lights)
            return _native->set_spot_lights(_native, p, (uint)lights.Length, null).Wrap();
    }

    /// <summary>
    /// Enables or disables screen-space ambient occlusion (SSAO).
    /// When enabled, a G-buffer pre-pass is performed each frame to compute per-pixel occlusion,
    /// which is then applied to the ambient term in the PBR shader.
    /// </summary>
    /// <param name="enabled">Whether SSAO is active.</param>
    /// <param name="radius">World-space hemisphere sample radius (default 0.5).</param>
    /// <param name="bias">Depth bias to prevent self-occlusion (default 0.025).</param>
    /// <param name="strength">Occlusion intensity multiplier (default 1.0).</param>
    [RequiresThread("ke.render")]
    public Result SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_ssao(_native, (byte)(enabled ? 1 : 0), radius, bias, strength, null).Wrap();
    }

    /// <summary>
    /// Configures the grid dimensions and light density limits for the Clustered Forward Shading pipeline.
    /// <paramref name="gridX"/> and <paramref name="gridY"/> are screen-space tiles; <paramref name="gridZ"/> is
    /// the logarithmic depth slices. Higher values improve culling accuracy at the cost of memory.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result SetClusterConfig(uint gridX, uint gridY, uint gridZ, uint maxLightsPerCluster, uint maxTotalLights)
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
        return _native->set_cluster_config(_native, &config, null).Wrap();
    }

    /// <summary>
    /// Uploads 6 RGBA8 face images into a GPU cubemap and returns a stable handle.
    /// <paramref name="faces"/> must contain exactly 6 arrays of equal size (width × height × 4 bytes each),
    /// ordered: +X, -X, +Y, -Y, +Z, -Z. All faces must be square and the same size.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result<TextureHandle> CreateCubemap(uint faceSize, byte[] data)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_texture_handle handle;
        fixed (byte* px = data)
        {
            var res = _native->create_cubemap_rgba(_native, faceSize, px, &handle, null);
            return res.Wrap(new TextureHandle(handle.idx));
        }
    }

    /// <summary>
    /// Submits the skybox draw call for the given cubemap handle. Call once per frame,
    /// after <see cref="SetViewTransform"/> and before other mesh submissions.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result SubmitSkybox(TextureHandle cubemapHandle)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->submit_skybox(_native, new ke_texture_handle { idx = cubemapHandle.Value }, null).Wrap();
    }

    /// <summary>Submits a draw call for a mesh using a material and world transform.</summary>
    [RequiresThread("ke.render")]
    public Result SubmitMesh(MeshHandle meshHandle, MaterialHandle materialHandle, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.render");
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        return _native->submit_mesh(_native, new ke_mesh_handle { idx = meshHandle.Value }, new ke_material_handle { idx = materialHandle.Value }, &mat, null).Wrap();
    }

    /// <summary>Allocates a GPU shadow map of the given dimensions. Returns a stable handle.</summary>
    [RequiresThread("ke.render")]
    public Result<ShadowMapHandle> CreateShadowMap(uint width, uint height)
    {
        KernelThread.AssertCurrent("ke.render");
        ke_shadow_map_handle handle;
        var res = _native->create_shadow_map(_native, width, height, &handle, null);
        return res.Wrap(new ShadowMapHandle(handle.idx));
    }

    /// <summary>Releases a shadow map and its GPU resources.</summary>
    [RequiresThread("ke.render")]
    public Result DestroyShadowMap(ShadowMapHandle handle)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->destroy_shadow_map(_native, new ke_shadow_map_handle { idx = handle.Value }, null).Wrap();
    }

    /// <summary>
    /// Begins the shadow depth pass for the given shadow map. Call once per frame before
    /// any <see cref="SubmitMeshShadow"/> calls. Stores the combined light VP for the Tree pass.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result BeginShadowPass(ShadowMapHandle shadowMapHandle, Matrix4x4 lightView, Matrix4x4 lightProj)
    {
        KernelThread.AssertCurrent("ke.render");
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref lightView);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref lightProj);
        return _native->begin_shadow_pass(_native, new ke_shadow_map_handle { idx = shadowMapHandle.Value }, &v, &p, null).Wrap();
    }

    /// <summary>Submits a mesh to the shadow depth pass. Call between Begin/EndShadowPass.</summary>
    [RequiresThread("ke.render")]
    public Result SubmitMeshShadow(MeshHandle meshHandle, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.render");
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        return _native->submit_mesh_shadow(_native, new ke_mesh_handle { idx = meshHandle.Value }, &mat, null).Wrap();
    }

    /// <summary>Ends the shadow depth pass. The shadow map is now available for Tree rendering.</summary>
    [RequiresThread("ke.render")]
    public Result EndShadowPass()
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->end_shadow_pass(_native, null).Wrap();
    }

    /// <summary>Overrides which shadow map is bound during the current frame's Tree pass.</summary>
    [RequiresThread("ke.render")]
    public Result SetShadowMap(ShadowMapHandle shadowMapHandle)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_shadow_map(_native, new ke_shadow_map_handle { idx = shadowMapHandle.Value }, null).Wrap();
    }

    /// <summary>
    /// Enables HDR tonemapping. When enabled, the Tree renders to an offscreen RGBA16F
    /// framebuffer; ACES tonemapping and gamma correction are applied before display.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_tonemapping(_native, (byte)(enabled ? 1 : 0), exposure, gamma, null).Wrap();
    }

    /// <summary>
    /// Enables bloom post-processing. Requires <see cref="SetTonemapping"/> to be active.
    /// Bright pixels above <paramref name="threshold"/> are blurred and additively composited.
    /// </summary>
    [RequiresThread("ke.render")]
    public Result SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f)
    {
        KernelThread.AssertCurrent("ke.render");
        return _native->set_bloom(_native, (byte)(enabled ? 1 : 0), threshold, intensity, null).Wrap();
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
