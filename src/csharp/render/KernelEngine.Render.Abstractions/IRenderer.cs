using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Native renderer interface. All operations run on <c>ke.render</c>.
/// Implementations marshal managed types (e.g. <see cref="Vertex"/>) to their native equivalents.
/// All methods throw <see cref="KernelError"/> on failure.
/// </summary>
/// <remarks>
/// Per-frame draw submission (lights, draw commands, post-process state) is performed via
/// <see cref="IFramePacket"/>, not directly on this interface — see Caso 3 of B5.1.
/// </remarks>
public interface IRenderer : IDisposable
{
    void Initialize();
    void Frame();
    void SubmitPacket(IFramePacket packet);

    void ClearColor(float r, float g, float b, float a);
    void ClearColor(Vector4 color);
    void SetOrthographic(bool enabled);
    void SetViewTransform(Matrix4x4 view, Matrix4x4 proj);

    /// <summary>The clip-space convention this backend expects matrices in. Valid after <see cref="Initialize"/>.</summary>
    NdcConvention GetNdcConvention();

    MeshHandle CreateMesh(Vertex[] vertices, ushort[] indices);
    void DestroyMesh(MeshHandle handle);

    TextureHandle CreateTexture(uint width, uint height, byte[] pixels);
    void DestroyTexture(TextureHandle handle);

    MaterialHandle CreateMaterial(float r, float g, float b, float a, TextureHandle textureHandle = default, float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default);
    MaterialHandle CreateMaterial(Vector4 color, TextureHandle textureHandle = default, float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default);
    void DestroyMaterial(MaterialHandle handle);

    void SetDirectionalLight(float dirX, float dirY, float dirZ, float r, float g, float b, float intensity);
    void SetAmbientLight(float r, float g, float b);
    void SetCameraPos(float x, float y, float z);

    void SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f);
    void SetClusterConfig(uint gridX, uint gridY, uint gridZ, uint maxLightsPerCluster, uint maxTotalLights);

    TextureHandle CreateCubemap(uint faceSize, byte[] data);
    void SubmitSkybox(TextureHandle cubemapHandle);
    void SubmitMesh(MeshHandle meshHandle, MaterialHandle materialHandle, Matrix4x4 transform);

    ShadowMapHandle CreateShadowMap(uint width, uint height);
    void DestroyShadowMap(ShadowMapHandle handle);
    void BeginShadowPass(ShadowMapHandle shadowMapHandle, Matrix4x4 lightView, Matrix4x4 lightProj);
    void SubmitMeshShadow(MeshHandle meshHandle, Matrix4x4 transform);
    void EndShadowPass();
    void SetShadowMap(ShadowMapHandle shadowMapHandle);

    void SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f);
    void SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f);

    /// <summary>Retrieves implementation-specific fatal error details (e.g., GPU crash reason).</summary>
    string? GetLastFatalError();
}
