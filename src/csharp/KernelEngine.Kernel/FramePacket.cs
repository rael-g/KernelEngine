using System.Numerics;
using KernelEngine.Kernel.Native;
using KernelEngine.Threading.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed view over a <c>ke_frame_packet*</c> owned by a <see cref="FrameSync"/> ring buffer.
/// Instances are short-lived: call <see cref="EndWrite"/> or <see cref="EndRead"/> to release the slot.
/// </summary>
public sealed unsafe class FramePacket
{
    private ke_frame_packet* _packet;
    private ke_frame_sync*   _sync;
    private readonly bool    _isWriter;

    public ke_frame_packet* NativePointer => _packet;

    internal FramePacket(ke_frame_packet* packet, ke_frame_sync* sync, bool isWriter)
    {
        _packet   = packet;
        _sync     = sync;
        _isWriter = isWriter;
    }

    // ── Sim-thread write API ──────────────────────────────────────────────────

    /// <summary>Sets the camera state for this frame.</summary>
    public void SetCamera(Matrix4x4 view, Matrix4x4 proj, Vector3 position)
    {
        _packet->camera.view  = ToKeMat4(view);
        _packet->camera.proj  = ToKeMat4(proj);
        _packet->camera.pos_x = position.X;
        _packet->camera.pos_y = position.Y;
        _packet->camera.pos_z = position.Z;
    }

    /// <summary>Sets the directional light for this frame.</summary>
    public void SetDirectionalLight(ke_directional_light light)
    {
        _packet->dir_light     = light;
        _packet->has_dir_light = true;
    }

    /// <summary>Appends a point light. Ignored when at capacity.</summary>
    public void AddPointLight(ke_point_light light)
    {
        if (_packet->point_light_count < _packet->point_light_capacity)
            _packet->point_lights[_packet->point_light_count++] = light;
    }

    /// <summary>Appends a spot light. Ignored when at capacity.</summary>
    public void AddSpotLight(ke_spot_light light)
    {
        if (_packet->spot_light_count < _packet->spot_light_capacity)
            _packet->spot_lights[_packet->spot_light_count++] = light;
    }

    /// <summary>Appends a draw command. Ignored when at capacity.</summary>
    public void AddDrawCommand(uint meshHandle, uint materialHandle, Matrix4x4 transform)
    {
        if (_packet->draw_count < _packet->draw_capacity)
        {
            ref var cmd = ref _packet->draw_commands[_packet->draw_count++];
            cmd.mesh_handle     = meshHandle;
            cmd.material_handle = materialHandle;
            cmd.transform       = ToKeMat4(transform);
        }
    }

    /// <summary>Sets the skybox cubemap handle for this frame.</summary>
    public void SetSkybox(uint cubemapHandle)
    {
        _packet->skybox_handle = cubemapHandle;
        _packet->has_skybox    = true;
    }

    /// <summary>Sets the shadow map data for this frame.</summary>
    public void SetShadow(uint mapHandle, Matrix4x4 lightView, Matrix4x4 lightProj)
    {
        _packet->shadow.map_handle  = mapHandle;
        _packet->shadow.light_view  = ToKeMat4(lightView);
        _packet->shadow.light_proj  = ToKeMat4(lightProj);
    }

    // ── Render-thread read API ────────────────────────────────────────────────

    /// <summary>Monotonically increasing frame counter.</summary>
    public ulong FrameNumber => _packet->frame_number;

    /// <summary>Camera view and projection matrices for this frame.</summary>
    public ke_frame_camera Camera => _packet->camera;

    /// <summary>Directional light, or <see langword="null"/> when absent.</summary>
    public ke_directional_light? DirectionalLight =>
        _packet->has_dir_light ? _packet->dir_light : null;

    /// <summary>Span over the point lights recorded this frame.</summary>
    public ReadOnlySpan<ke_point_light> PointLights =>
        new(_packet->point_lights, (int)_packet->point_light_count);

    /// <summary>Span over the spot lights recorded this frame.</summary>
    public ReadOnlySpan<ke_spot_light> SpotLights =>
        new(_packet->spot_lights, (int)_packet->spot_light_count);

    /// <summary>Span over the draw commands recorded this frame.</summary>
    public ReadOnlySpan<ke_draw_command> DrawCommands =>
        new(_packet->draw_commands, (int)_packet->draw_count);

    /// <summary>Skybox cubemap handle, or <c>uint.MaxValue</c> when absent.</summary>
    public uint SkyboxHandle => _packet->skybox_handle;

    /// <summary>Whether a skybox was submitted this frame.</summary>
    public bool HasSkybox => _packet->has_skybox;

    /// <summary>Shadow map data for this frame.</summary>
    public ke_frame_shadow Shadow => _packet->shadow;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    /// <summary>
    /// Signals that the sim thread has finished writing. The packet becomes available for reading.
    /// </summary>
    public void EndWrite()
    {
        if (_packet == null) return;
        _sync->end_write(_sync);
        _packet = null;
    }

    /// <summary>
    /// Signals that the render thread has finished reading. The slot is returned to the write pool.
    /// </summary>
    public void EndRead()
    {
        if (_packet == null) return;
        _sync->end_read(_sync);
        _packet = null;
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static ke_mat4 ToKeMat4(Matrix4x4 m)
    {
        ke_mat4 r = default;
        r.m[0]  = m.M11; r.m[1]  = m.M12; r.m[2]  = m.M13; r.m[3]  = m.M14;
        r.m[4]  = m.M21; r.m[5]  = m.M22; r.m[6]  = m.M23; r.m[7]  = m.M24;
        r.m[8]  = m.M31; r.m[9]  = m.M32; r.m[10] = m.M33; r.m[11] = m.M34;
        r.m[12] = m.M41; r.m[13] = m.M42; r.m[14] = m.M43; r.m[15] = m.M44;
        return r;
    }
}
