using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Snapshot of one rendered frame, written by simulation systems and consumed by the renderer.
/// All methods are safe (no <c>unsafe</c> on caller side); the concrete <c>FramePacket</c>
/// in <c>KernelEngine.Kernel</c> marshals each call to the native <c>ke_frame_packet</c> layout.
/// </summary>
public interface IFramePacket
{
    /// <summary>Monotonically increasing frame counter.</summary>
    ulong FrameNumber { get; }

    // ── Per-frame state (writers) ────────────────────────────────────────────

    /// <summary>Background color cleared at the start of the frame.</summary>
    void SetClearColor(float r, float g, float b, float a);

    /// <summary>Ambient light color used for the scene (constant per frame).</summary>
    void SetAmbientLight(float r, float g, float b);

    /// <summary>Camera state for this frame (view / projection / world-space position).</summary>
    void SetCamera(Matrix4x4 view, Matrix4x4 projection, Vector3 position);

    /// <summary>Sets the directional (sun) light for this frame.</summary>
    void SetDirectionalLight(DirectionalLight light);

    /// <summary>Appends a point light. Ignored when the per-frame capacity is exhausted.</summary>
    void AddPointLight(PointLight light);

    /// <summary>Appends a spot light. Ignored when the per-frame capacity is exhausted.</summary>
    void AddSpotLight(SpotLight light);

    /// <summary>Appends a draw command to the main scene pass. Ignored when capacity is exhausted.</summary>
    void AddDrawCommand(MeshHandle mesh, MaterialHandle material, Matrix4x4 transform);

    /// <summary>Appends a draw command to the shadow depth pass. Ignored when capacity is exhausted.</summary>
    void AddShadowDrawCommand(MeshHandle mesh, Matrix4x4 transform);

    /// <summary>Sets the skybox cubemap for this frame.</summary>
    void SetSkybox(TextureHandle cubemap);

    /// <summary>Sets the shadow map handle + light view/proj for the depth pass.</summary>
    void SetShadow(ShadowMapHandle map, Matrix4x4 lightView, Matrix4x4 lightProjection);

    /// <summary>Overrides the active shadow map handle for the main scene pass.</summary>
    void SetActiveShadowMap(ShadowMapHandle handle);

    // ── Post-process state ───────────────────────────────────────────────────

    void SetSsao(bool enabled, float radius, float bias, float strength);
    void SetTonemapping(bool enabled, float exposure, float gamma);
    void SetBloom(bool enabled, float threshold, float intensity);

    // ── Lifecycle ────────────────────────────────────────────────────────────

    /// <summary>Releases this packet back to the writer pool. Called by the render thread.</summary>
    void EndRead();

    /// <summary>Releases this packet to the reader (sim thread → render thread). Called by sim.</summary>
    void EndWrite();
}
