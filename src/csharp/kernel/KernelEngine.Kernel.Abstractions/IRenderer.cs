using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Native renderer interface. All operations run on <c>ke.render</c>.
/// Implementations marshal managed types (e.g. <see cref="Vertex"/>) to their native equivalents.
/// </summary>
/// <remarks>
/// Per-frame draw submission (lights, draw commands, post-process state) is performed via
/// <see cref="IFramePacket"/>, not directly on this interface — see Caso 3 of B5.1.
/// </remarks>
public interface IRenderer : IDisposable
{
    void Initialize();
    Result Frame();
    Result SubmitPacket(IFramePacket packet);

    Result ClearColor(float r, float g, float b, float a);
    Result ClearColor(Vector4 color);
    Result SetOrthographic(bool enabled);
    Result SetViewTransform(Matrix4x4 view, Matrix4x4 proj);

    /// <summary>The clip-space convention this backend expects matrices in. Valid after <see cref="Initialize"/>.</summary>
    NdcConvention GetNdcConvention();

    Result<MeshHandle> CreateMesh(Vertex[] vertices, ushort[] indices);
    Result DestroyMesh(MeshHandle handle);

    Result<TextureHandle> CreateTexture(uint width, uint height, byte[] pixels);
    Result DestroyTexture(TextureHandle handle);

    Result<MaterialHandle> CreateMaterial(float r, float g, float b, float a, TextureHandle textureHandle = default, float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default);
    Result<MaterialHandle> CreateMaterial(Vector4 color, TextureHandle textureHandle = default, float metallic = 0f, float roughness = 0.5f, TextureHandle normalMapHandle = default);
    Result DestroyMaterial(MaterialHandle handle);

    Result SetDirectionalLight(float dirX, float dirY, float dirZ, float r, float g, float b, float intensity);
    Result SetAmbientLight(float r, float g, float b);
    Result SetCameraPos(float x, float y, float z);

    Result SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f);
    Result SetClusterConfig(uint gridX, uint gridY, uint gridZ, uint maxLightsPerCluster, uint maxTotalLights);

    Result<TextureHandle> CreateCubemap(uint faceSize, byte[] data);
    Result SubmitSkybox(TextureHandle cubemapHandle);
    Result SubmitMesh(MeshHandle meshHandle, MaterialHandle materialHandle, Matrix4x4 transform);

    Result<ShadowMapHandle> CreateShadowMap(uint width, uint height);
    Result DestroyShadowMap(ShadowMapHandle handle);
    Result BeginShadowPass(ShadowMapHandle shadowMapHandle, Matrix4x4 lightView, Matrix4x4 lightProj);
    Result SubmitMeshShadow(MeshHandle meshHandle, Matrix4x4 transform);
    Result EndShadowPass();
    Result SetShadowMap(ShadowMapHandle shadowMapHandle);

    Result SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f);
    Result SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f);

    /// <summary>Retrieves implementation-specific fatal error details (e.g., GPU crash reason).</summary>
    string? GetLastFatalError();
}
