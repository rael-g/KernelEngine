using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Reads all active light components each frame and uploads them to the renderer.
/// Handles directional, point, and spot lights. Must run before <see cref="MeshRenderSystem"/>.
/// </summary>
public sealed unsafe class LightRenderSystem : ISystem
{
    private readonly Renderer _renderer;

    // Reusable upload buffers (avoids allocation per frame)
    private ke_point_light[] _pointBuf = new ke_point_light[8];
    private ke_spot_light[]  _spotBuf  = new ke_spot_light[8];

    public LightRenderSystem(Renderer renderer) => _renderer = renderer;

    public void Update(World world, float dt)
    {
        // ── Directional light ──────────────────────────────────────────────────
        if (LightNode.ComponentId != uint.MaxValue)
        {
            var (_, lights) = world.Registry.Query<LightComponent>(LightNode.ComponentId);
            if (lights.Length > 0)
            {
                ref readonly var light = ref lights[0];
                _renderer.SetDirectionalLight(
                    light.DirX, light.DirY, light.DirZ,
                    light.R, light.G, light.B, light.Intensity);
            }
        }

        // ── Point lights ───────────────────────────────────────────────────────
        if (PointLightNode.ComponentId != uint.MaxValue)
        {
            var (entities, comps) = world.Registry.Query<PointLightComponent>(PointLightNode.ComponentId);
            int count = Math.Min(entities.Length, _pointBuf.Length);
            for (int i = 0; i < count; i++)
            {
                var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
                ref readonly var c = ref comps[i];
                _pointBuf[i] = new ke_point_light
                {
                    pos_x = tc != null ? tc->WorldMatrix.M41 : 0f,
                    pos_y = tc != null ? tc->WorldMatrix.M42 : 0f,
                    pos_z = tc != null ? tc->WorldMatrix.M43 : 0f,
                    radius    = c.Radius,
                    r         = c.R,
                    g         = c.G,
                    b         = c.B,
                    intensity = c.Intensity,
                };
            }
            _renderer.SetPointLights(_pointBuf.AsSpan(0, count));
        }

        // ── Spot lights ────────────────────────────────────────────────────────
        if (SpotLightNode.ComponentId != uint.MaxValue)
        {
            var (entities, comps) = world.Registry.Query<SpotLightComponent>(SpotLightNode.ComponentId);
            int count = Math.Min(entities.Length, _spotBuf.Length);
            for (int i = 0; i < count; i++)
            {
                var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
                ref readonly var c = ref comps[i];
                _spotBuf[i] = new ke_spot_light
                {
                    pos_x       = tc != null ? tc->WorldMatrix.M41 : 0f,
                    pos_y       = tc != null ? tc->WorldMatrix.M42 : 0f,
                    pos_z       = tc != null ? tc->WorldMatrix.M43 : 0f,
                    range       = c.Range,
                    dir_x       = c.DirX,
                    dir_y       = c.DirY,
                    dir_z       = c.DirZ,
                    inner_angle = c.InnerAngle,
                    r           = c.R,
                    g           = c.G,
                    b           = c.B,
                    intensity   = c.Intensity,
                    outer_angle = c.OuterAngle,
                };
            }
            _renderer.SetSpotLights(_spotBuf.AsSpan(0, count));
        }
    }
}
