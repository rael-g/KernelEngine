using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Hardware-accelerated renderer. Takes ownership of a <c>ke_render*</c> created by a service factory,
/// calls <c>on_initialize</c> on construction, and <c>on_shutdown</c>/<c>destroy</c> on disposal.
/// </summary>
public sealed unsafe class Renderer : IDisposable
{
    private ke_render* _native;

    public ke_render* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    /// <summary>
    /// Wraps an already-created <c>ke_render*</c> and calls <c>on_initialize</c>.
    /// </summary>
    public Renderer(ke_render* native)
    {
        _native = native;
        // In constructor we still throw because if initialization fails, the object is unusable.
        KernelException.ThrowIfFailed(_native->on_initialize(_native));
    }

    /// <summary>Advances to the next frame and presents the current one. Call once per loop iteration.</summary>
    public Result Frame() => _native->frame(_native);

    /// <summary>Sets the background clear color for the next frame.</summary>
    public Result ClearColor(float r, float g, float b, float a) => _native->clear_color(_native, r, g, b, a);

    /// <summary>Sets the background clear color for the next frame.</summary>
    public Result ClearColor(Vector4 color) => ClearColor(color.X, color.Y, color.Z, color.W);

    /// <summary>Toggles orthographic projection mode.</summary>
    public Result SetOrthographic(bool enabled) => _native->set_orthographic(_native, enabled);

    /// <summary>Sets the view and projection matrices for the active view. Call once per frame before draw calls.</summary>
    public Result SetViewTransform(Matrix4x4 view, Matrix4x4 proj)
    {
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref view);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref proj);
        return _native->set_view_transform(_native, &v, &p);
    }

    /// <summary>Uploads geometry to the GPU and returns a stable mesh handle.</summary>
    public Result<uint> CreateMesh(ke_vertex[] vertices, ushort[] indices)
    {
        uint handle;
        fixed (ke_vertex* vp = vertices)
        fixed (ushort* ip = indices)
        {
            var res = _native->create_mesh(_native, vp, (uint)vertices.Length, ip, (uint)indices.Length, &handle);
            return new Result<uint>(res, handle);
        }
    }

    /// <summary>Releases GPU resources for a mesh handle.</summary>
    public Result DestroyMesh(uint handle) => _native->destroy_mesh(_native, handle);

    /// <summary>Uploads raw RGBA8 pixel data to the GPU and returns a stable texture handle.</summary>
    public Result<uint> CreateTexture(uint width, uint height, byte[] pixels)
    {
        uint handle;
        fixed (byte* px = pixels)
        {
            var res = _native->create_texture_rgba(_native, width, height, px, &handle);
            return new Result<uint>(res, handle);
        }
    }

    /// <summary>Releases GPU resources for a texture handle.</summary>
    public Result DestroyTexture(uint handle) => _native->destroy_texture(_native, handle);

    /// <summary>Creates a material from properties, returning a stable handle.</summary>
    public Result<uint> CreateMaterial(float r, float g, float b, float a, uint textureHandle = 0,
                               float metallic = 0f, float roughness = 0.5f)
    {
        uint handle;
        var mat = new ke_material { r = r, g = g, b = b, a = a, albedo = textureHandle,
                                    metallic = metallic, roughness = roughness };
        var res = _native->create_material(_native, &mat, &handle);
        return new Result<uint>(res, handle);
    }

    /// <inheritdoc cref="CreateMaterial(float,float,float,float,uint,float,float)"/>
    public Result<uint> CreateMaterial(Vector4 color, uint textureHandle = 0,
                               float metallic = 0f, float roughness = 0.5f) =>
        CreateMaterial(color.X, color.Y, color.Z, color.W, textureHandle, metallic, roughness);

    /// <summary>Releases a material handle.</summary>
    public Result DestroyMaterial(uint handle) => _native->destroy_material(_native, handle);

    /// <summary>Sets the active directional light for the current frame.</summary>
    public Result SetDirectionalLight(float dirX, float dirY, float dirZ,
                                    float r, float g, float b, float intensity)
    {
        var light = new ke_directional_light
        {
            dir_x = dirX, dir_y = dirY, dir_z = dirZ,
            r = r, g = g, b = b, intensity = intensity,
        };
        return _native->set_directional_light(_native, &light);
    }

    /// <summary>Sets the ambient light color for the current frame.</summary>
    public Result SetAmbientLight(float r, float g, float b) => _native->set_ambient_light(_native, r, g, b);

    /// <summary>Sets the camera world-space position used for PBR specular calculations. Call once per frame.</summary>
    public Result SetCameraPos(float x, float y, float z) => _native->set_camera_pos(_native, x, y, z);

    /// <summary>
    /// Uploads 6 RGBA8 face images into a GPU cubemap and returns a stable handle.
    /// <paramref name="faces"/> must contain exactly 6 arrays of equal size (width × height × 4 bytes each),
    /// ordered: +X, -X, +Y, -Y, +Z, -Z. All faces must be square and the same size.
    /// </summary>
    public Result<uint> CreateCubemap(uint faceSize, byte[] data)
    {
        uint handle;
        fixed (byte* px = data)
        {
            var res = _native->create_cubemap_rgba(_native, faceSize, px, &handle);
            return new Result<uint>(res, handle);
        }
    }

    /// <summary>
    /// Submits the skybox draw call for the given cubemap handle. Call once per frame,
    /// after <see cref="SetViewTransform"/> and before other mesh submissions.
    /// </summary>
    public Result SubmitSkybox(uint cubemapHandle) => _native->submit_skybox(_native, cubemapHandle);

    /// <summary>Submits a draw call for a mesh using a material and world transform.</summary>
    public Result SubmitMesh(uint meshHandle, uint materialHandle, Matrix4x4 transform)
    {
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        return _native->submit_mesh(_native, meshHandle, materialHandle, &mat);
    }

    /// <summary>Allocates a GPU shadow map of the given dimensions. Returns a stable handle.</summary>
    public Result<uint> CreateShadowMap(uint width, uint height)
    {
        uint handle;
        var res = _native->create_shadow_map(_native, width, height, &handle);
        return new Result<uint>(res, handle);
    }

    /// <summary>Releases a shadow map and its GPU resources.</summary>
    public Result DestroyShadowMap(uint handle) => _native->destroy_shadow_map(_native, handle);

    /// <summary>
    /// Begins the shadow depth pass for the given shadow map. Call once per frame before
    /// any <see cref="SubmitMeshShadow"/> calls. Stores the combined light VP for the scene pass.
    /// </summary>
    public Result BeginShadowPass(uint shadowMapHandle, Matrix4x4 lightView, Matrix4x4 lightProj)
    {
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref lightView);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref lightProj);
        return _native->begin_shadow_pass(_native, shadowMapHandle, &v, &p);
    }

    /// <summary>Submits a mesh to the shadow depth pass. Call between Begin/EndShadowPass.</summary>
    public Result SubmitMeshShadow(uint meshHandle, Matrix4x4 transform)
    {
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        return _native->submit_mesh_shadow(_native, meshHandle, &mat);
    }

    /// <summary>Ends the shadow depth pass. The shadow map is now available for scene rendering.</summary>
    public Result EndShadowPass() => _native->end_shadow_pass(_native);

    /// <summary>Overrides which shadow map is bound during the current frame's scene pass.</summary>
    public Result SetShadowMap(uint shadowMapHandle) => _native->set_shadow_map(_native, shadowMapHandle);

    public void Dispose()
    {
        if (_native != null)
        {
            _native->on_shutdown(_native);
            _native->destroy(_native);
            _native = null;
        }
    }
}
