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

    public LightRenderSystem(Renderer renderer) => _renderer = renderer;

    public void Update(World world, float dt, FramePacket? packet = null)
    {
        if (packet == null) return;

        // ── Directional light ──────────────────────────────────────────────────
        if (LightNode.ComponentId != uint.MaxValue)
        {
            var (_, lights) = world.Registry.Query<LightComponent>(LightNode.ComponentId);
            if (lights.Length > 0)
            {
                ref readonly var light = ref lights[0];
                packet.SetDirectionalLight(new ke_directional_light
                {
                    dir_x = light.DirX, dir_y = light.DirY, dir_z = light.DirZ,
                    r = light.R, g = light.G, b = light.B, intensity = light.Intensity,
                });
            }
        }

        // ── Point lights ───────────────────────────────────────────────────────
        if (PointLightNode.ComponentId != uint.MaxValue)
        {
            var (entities, comps) = world.Registry.Query<PointLightComponent>(PointLightNode.ComponentId);
            for (int i = 0; i < entities.Length; i++)
            {
                var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
                ref readonly var c = ref comps[i];
                packet.AddPointLight(new ke_point_light
                {
                    pos_x = tc != null ? tc->WorldMatrix.M41 : 0f,
                    pos_y = tc != null ? tc->WorldMatrix.M42 : 0f,
                    pos_z = tc != null ? tc->WorldMatrix.M43 : 0f,
                    radius    = c.Radius,
                    r         = c.R,
                    g         = c.G,
                    b         = c.B,
                    intensity = c.Intensity,
                });
            }
        }

        // ── Spot lights ────────────────────────────────────────────────────────
        if (SpotLightNode.ComponentId != uint.MaxValue)
        {
            var (entities, comps) = world.Registry.Query<SpotLightComponent>(SpotLightNode.ComponentId);
            for (int i = 0; i < entities.Length; i++)
            {
                var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
                ref readonly var c = ref comps[i];
                packet.AddSpotLight(new ke_spot_light
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
                });
            }
        }
    }
}
