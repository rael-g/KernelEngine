using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Renders a directional shadow map each frame using the first active <see cref="LightComponent"/>.
/// Must run before <see cref="MeshRenderSystem"/> so the depth texture is ready for scene sampling.
/// </summary>
public sealed unsafe class ShadowRenderSystem : ISystem
{
    private readonly Renderer _renderer;
    private uint _shadowMapHandle = uint.MaxValue;

    /// <summary>Shadow map resolution in texels (width and height).</summary>
    public uint Resolution { get; }

    /// <summary>Half-size of the orthographic light frustum in world units.</summary>
    public float FrustumSize { get; }

    /// <summary>Far plane distance of the light frustum in world units.</summary>
    public float FarPlane { get; }

    public ShadowRenderSystem(Renderer renderer, uint resolution = 1024,
                               float frustumSize = 20f, float farPlane = 50f)
    {
        _renderer   = renderer;
        Resolution  = resolution;
        FrustumSize = frustumSize;
        FarPlane    = farPlane;
    }

    public void Update(World world, float dt, FramePacket? packet = null)
    {
        if (LightNode.ComponentId == uint.MaxValue || packet == null) return;

        var (_, lights) = world.Registry.Query<LightComponent>(LightNode.ComponentId);
        if (lights.Length == 0) return;

        // Lazy-create shadow map on first use (safe outside render pass).
        if (_shadowMapHandle == uint.MaxValue)
        {
            var createRes = _renderer.CreateShadowMap(Resolution, Resolution);
            _shadowMapHandle = createRes.Value;
            KernelException.ThrowIfFailed(createRes.Code, nameof(_renderer.CreateShadowMap));
        }

        ref readonly var light = ref lights[0];
        var lightDir = Vector3.Normalize(new Vector3(light.DirX, light.DirY, light.DirZ));

        // Position the light camera far back along its direction.
        var lightPos  = -lightDir * (FarPlane * 0.5f);
        var up        = MathF.Abs(Vector3.Dot(lightDir, Vector3.UnitY)) > 0.99f
                        ? Vector3.UnitX
                        : Vector3.UnitY;
        var lightView = Matrix4x4.CreateLookAt(lightPos, Vector3.Zero, up);
        var lightProj = Matrix4x4.CreateOrthographic(FrustumSize, FrustumSize, 0.1f, FarPlane);

        // Record shadow pass state into the packet
        packet.SetShadow(_shadowMapHandle, lightView, lightProj);

        // Record shadow casters
        if (MeshNode.ComponentId != uint.MaxValue)
        {
            var (entities, meshComps) = world.Registry.Query<MeshComponent>(MeshNode.ComponentId);
            for (int i = 0; i < entities.Length; i++)
            {
                if (meshComps[i].MeshHandle == uint.MaxValue) continue;
                var tc = world.Registry.GetComponent<TransformComponent>(
                    entities[i], world.TransformComponentId);
                if (tc != null)
                {
                    packet.AddShadowDrawCommand(meshComps[i].MeshHandle, tc->WorldMatrix);
                }
            }
        }
    }
}
