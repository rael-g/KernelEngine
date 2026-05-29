using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Mediates per-frame Tree commands. These commands are recorded into a frame packet
/// and executed by the renderer at the end of the frame.
/// MUST be called from the simulation thread.
/// </summary>
public interface ISceneWriter
{
    void ClearColor(float r, float g, float b, float a = 1.0f);
    void ClearColor(Vector4 color) => ClearColor(color.X, color.Y, color.Z, color.W);

    void SetAmbientLight(float r, float g, float b);
    void SetAmbientLight(Vector3 color) => SetAmbientLight(color.X, color.Y, color.Z);

    void SetCamera(Matrix4x4 view, Matrix4x4 projection, Vector3 position);

    void SetDirectionalLight(Vector3 direction, Vector3 color, float intensity);

    void AddDrawCommand(MeshHandle mesh, MaterialHandle material, Matrix4x4 transform);

    /// <summary>
    /// Records a screen-space textured quad for the UI overlay pass (drawn after main scene + post-fx).
    /// Coordinates are backbuffer pixels (top-left origin); UVs are normalized; color is premultiplied
    /// alpha. Pass <see cref="TextureHandle.None"/> for a flat-colored quad — bgfx supplies a default
    /// white texture so the tint becomes the rendered color.
    /// </summary>
    void AddUiQuadCommand(TextureHandle texture,
                          float dstX, float dstY, float dstW, float dstH,
                          float u0, float v0, float u1, float v1,
                          Vector4 color);

    void SetSkybox(TextureHandle cubemap);

    void BeginShadowPass(ShadowMapHandle shadowMap, Matrix4x4 lightView, Matrix4x4 lightProjection);
    void AddShadowDrawCommand(MeshHandle mesh, Matrix4x4 transform);
    void EndShadowPass();

    void SetShadowMap(ShadowMapHandle shadowMap);

    // Advanced pipeline settings
    void SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f);
    void SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f);
    void SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f);
}
