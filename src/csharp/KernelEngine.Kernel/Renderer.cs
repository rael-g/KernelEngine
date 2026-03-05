using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// Hardware-accelerated renderer. Takes ownership of a <c>ke_render*</c> created by a plugin factory,
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
        KernelException.ThrowIfFailed(_native->on_initialize(_native));
    }

    /// <summary>Advances to the next frame and presents the current one. Call once per loop iteration.</summary>
    public void Frame() =>
        KernelException.ThrowIfFailed(_native->frame(_native));

    /// <summary>Sets the background clear color for the next frame.</summary>
    public void ClearColor(float r, float g, float b, float a) =>
        KernelException.ThrowIfFailed(_native->clear_color(_native, r, g, b, a));

    /// <summary>Sets the background clear color for the next frame.</summary>
    public void ClearColor(Vector4 color) =>
        ClearColor(color.X, color.Y, color.Z, color.W);

    /// <summary>Toggles orthographic projection mode.</summary>
    public void SetOrthographic(bool enabled) =>
        KernelException.ThrowIfFailed(_native->set_orthographic(_native, enabled));

    /// <summary>Sets the view and projection matrices for the active view. Call once per frame before draw calls.</summary>
    public void SetViewTransform(Matrix4x4 view, Matrix4x4 proj)
    {
        var v = Unsafe.As<Matrix4x4, ke_mat4>(ref view);
        var p = Unsafe.As<Matrix4x4, ke_mat4>(ref proj);
        KernelException.ThrowIfFailed(_native->set_view_transform(_native, &v, &p));
    }

    /// <summary>Uploads geometry to the GPU and returns a stable mesh handle.</summary>
    public uint CreateMesh(ke_vertex[] vertices, ushort[] indices)
    {
        uint handle;
        fixed (ke_vertex* vp = vertices)
        fixed (ushort* ip = indices)
            KernelException.ThrowIfFailed(
                _native->create_mesh(_native, vp, (uint)vertices.Length, ip, (uint)indices.Length, &handle));
        return handle;
    }

    /// <summary>Releases GPU resources for a mesh handle.</summary>
    public void DestroyMesh(uint handle) =>
        KernelException.ThrowIfFailed(_native->destroy_mesh(_native, handle));

    /// <summary>Uploads raw RGBA8 pixel data to the GPU and returns a stable texture handle.</summary>
    public uint CreateTexture(uint width, uint height, byte[] pixels)
    {
        uint handle;
        fixed (byte* px = pixels)
            KernelException.ThrowIfFailed(_native->create_texture_rgba(_native, width, height, px, &handle));
        return handle;
    }

    /// <summary>Releases GPU resources for a texture handle.</summary>
    public void DestroyTexture(uint handle) =>
        KernelException.ThrowIfFailed(_native->destroy_texture(_native, handle));

    /// <summary>Creates a material from a color tint and optional albedo texture, returning a stable handle.</summary>
    public uint CreateMaterial(float r, float g, float b, float a, uint textureHandle = 0,
                               float metallic = 0f, float roughness = 0.5f)
    {
        uint handle;
        var desc = new ke_material_descriptor { r = r, g = g, b = b, a = a, albedo = textureHandle,
                                                metallic = metallic, roughness = roughness };
        KernelException.ThrowIfFailed(_native->create_material(_native, &desc, &handle));
        return handle;
    }

    /// <inheritdoc cref="CreateMaterial(float,float,float,float,uint,float,float)"/>
    public uint CreateMaterial(Vector4 color, uint textureHandle = 0,
                               float metallic = 0f, float roughness = 0.5f) =>
        CreateMaterial(color.X, color.Y, color.Z, color.W, textureHandle, metallic, roughness);

    /// <summary>Releases a material handle.</summary>
    public void DestroyMaterial(uint handle) =>
        KernelException.ThrowIfFailed(_native->destroy_material(_native, handle));

    /// <summary>Sets the active directional light for the current frame.</summary>
    public void SetDirectionalLight(float dirX, float dirY, float dirZ,
                                    float r, float g, float b, float intensity)
    {
        var light = new ke_directional_light
        {
            dir_x = dirX, dir_y = dirY, dir_z = dirZ,
            r = r, g = g, b = b, intensity = intensity,
        };
        KernelException.ThrowIfFailed(_native->set_directional_light(_native, &light));
    }

    /// <summary>Sets the ambient light color for the current frame.</summary>
    public void SetAmbientLight(float r, float g, float b) =>
        KernelException.ThrowIfFailed(_native->set_ambient_light(_native, r, g, b));

    /// <summary>Sets the camera world-space position used for PBR specular calculations. Call once per frame.</summary>
    public void SetCameraPos(float x, float y, float z) =>
        KernelException.ThrowIfFailed(_native->set_camera_pos(_native, x, y, z));

    /// <summary>
    /// Uploads 6 RGBA8 face images into a GPU cubemap and returns a stable handle.
    /// <paramref name="faces"/> must contain exactly 6 arrays of equal size (width × height × 4 bytes each),
    /// ordered: +X, -X, +Y, -Y, +Z, -Z. All faces must be square and the same size.
    /// </summary>
    public uint CreateCubemap(uint faceSize, byte[] data)
    {
        uint handle;
        fixed (byte* px = data)
            KernelException.ThrowIfFailed(_native->create_cubemap_rgba(_native, faceSize, px, &handle));
        return handle;
    }

    /// <summary>
    /// Submits the skybox draw call for the given cubemap handle. Call once per frame,
    /// after <see cref="SetViewTransform"/> and before other mesh submissions.
    /// </summary>
    public void SubmitSkybox(uint cubemapHandle) =>
        KernelException.ThrowIfFailed(_native->submit_skybox(_native, cubemapHandle));

    /// <summary>Submits a draw call for a mesh using a material and world transform.</summary>
    public void SubmitMesh(uint meshHandle, uint materialHandle, Matrix4x4 transform)
    {
        var mat = Unsafe.As<Matrix4x4, ke_mat4>(ref transform);
        KernelException.ThrowIfFailed(_native->submit_mesh(_native, meshHandle, materialHandle, &mat));
    }

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
