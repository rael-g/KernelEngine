using System.Numerics;
using KernelEngine.Framework.Legacy.Internal;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Pure-managed shadow render system. Reads the first directional light, positions an
/// orthographic shadow camera, and enqueues every valid mesh as a shadow caster via the
/// safe <see cref="IFramePacket"/> API.
/// </summary>
/// <remarks>
/// The shadow map handle is injected by ke.render after GPU initialization via
/// <see cref="SetShadowMap"/>. Until set, the system silently skips its work
/// (no shadow casters submitted), so the renderer falls back to unshadowed lighting.
/// </remarks>
public sealed class ShadowRenderSystem : ISystem
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

    public void Update(IWorld world, float dt, IFramePacket? packet = null, IInputReader? input = null)
    {
        if (packet == null) return;
        if (_shadowMap == ShadowMapHandle.None) return;
        var registry = world.Registry;

        // ── Directional light → shadow camera ──────────────────────────────────
        var lights = registry.Query<LightComponent>(_lightCid);
        if (lights.Length == 0) return;

        var l = lights.Data[0];
        // LightComponent.Direction is the direction TO the sun (matches the PBR shader's
        // `vec3 L = normalize(u_lightDir.xyz)` with no negation — L is the toward-light
        // vector). So eye = +dir × distance places the sun camera AT the sun's position.
        // Combined with the RH LookAt fix in ViewProjection, origin lands at negative
        // view-space z inside the Ortho frustum (OBS.7 resolution path).
        var eye = new Vector3(l.DirX * 25f, l.DirY * 25f, l.DirZ * 25f);
        var view = ViewProjection.LookAt(eye, Vector3.Zero, Vector3.UnitY);
        var proj = ViewProjection.Ortho(-20f, 20f, -20f, 20f, 0.1f, 50f);
        packet.SetShadow(_shadowMap, view, proj);

        // ── Shadow casters ─────────────────────────────────────────────────────
        var meshes = registry.Query<MeshComponent>(_meshCid);
        for (int i = 0; i < meshes.Length; i++)
        {
            var mesh = meshes.Data[i];
            if (mesh.MeshHandle == MeshHandle.None) continue;

            Matrix4x4 worldMatrix;
            { var slot = registry.GetComponent<TransformComponent>(meshes.Entities[i], _transformCid); if (slot.IsEmpty) continue; worldMatrix = slot[0].WorldMatrix; }

            packet.AddShadowDrawCommand(mesh.MeshHandle, worldMatrix);
        }
    }

    public ComponentAccess GetAccess() => new()
    {
        Reads = [_lightCid, _meshCid, _transformCid],
        Writes = []
    };
}
