using System.Runtime.CompilerServices;
using System.Threading;
using KernelEngine.Framework.Internal;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Pure-managed shadow render system. Reads the first directional light, positions an
/// orthographic shadow camera, and enqueues every valid mesh as a shadow caster.
/// Replaces the legacy C++ ShadowSystem.
/// </summary>
/// <remarks>
/// The shadow map handle is injected by ke.render after GPU initialization via
/// <see cref="SetShadowMap"/>. Until set, the system silently skips its work
/// (no shadow casters submitted), so the renderer falls back to unshadowed lighting.
/// </remarks>
public sealed unsafe class ShadowRenderSystem : ISystem
{
    private readonly uint _lightCid;
    private readonly uint _meshCid;
    private readonly uint _transformCid;
    private ShadowMapHandle _shadowMap = ShadowMapHandle.None;

    public ShadowRenderSystem(uint lightCid, uint meshCid, uint transformCid)
    {
        _lightCid = lightCid;
        _meshCid = meshCid;
        _transformCid = transformCid;
    }

    /// <summary>Assigns the GPU shadow map to render into. Must be called from ke.render after GPU init.</summary>
    public void SetShadowMap(ShadowMapHandle handle) => _shadowMap = handle;

    public void Update(World world, float dt, FramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        if (_shadowMap == ShadowMapHandle.None) return;

        var registry = world.Registry;
        var raw = packet.NativePointer;

        // ── Directional light → shadow camera ──────────────────────────────────
        var lights = registry.Query<LightComponent>(_lightCid);
        if (lights.Length == 0) return;

        var l = lights.Data[0];
        // Position the shadow camera along +dir (toward the light) at radius 25 looking at the origin.
        Mat4.LookAt((float*)&raw->shadow.light_view.m,
            l.DirX * 25f, l.DirY * 25f, l.DirZ * 25f,
            0f, 0f, 0f,
            0f, 1f, 0f);
        Mat4.Ortho((float*)&raw->shadow.light_proj.m, -20f, 20f, -20f, 20f, 0.1f, 50f);
        raw->shadow.map_handle = new ke_shadow_map_handle { idx = _shadowMap.Value };

        // ── Shadow casters ─────────────────────────────────────────────────────
        var meshes = registry.Query<MeshComponent>(_meshCid);
        for (int i = 0; i < meshes.Length; i++)
        {
            var mesh = meshes.Data[i];
            if (mesh.MeshHandle == MeshHandle.None) continue;

            var tc = registry.GetComponent<TransformComponent>(meshes.Entities[i], _transformCid);
            if (tc == null) continue;

            uint index = (uint)Interlocked.Increment(ref Unsafe.As<uint, int>(ref raw->shadow_draw_count)) - 1;
            if (index < raw->shadow_draw_capacity)
            {
                var cmd = &raw->shadow_draw_commands[index];
                cmd->mesh_handle = new ke_mesh_handle { idx = mesh.MeshHandle.Value };
                cmd->material_handle = new ke_material_handle { idx = uint.MaxValue }; // KE_MATERIAL_NONE
                cmd->transform = Unsafe.As<System.Numerics.Matrix4x4, ke_mat4>(ref tc->WorldMatrix);
            }
        }
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_lightCid, _meshCid, _transformCid],
        Writes = []
    };
}
