using KernelEngine;

namespace KernelEngine.Framework;

/// <summary>
/// Reads the first active <see cref="LightComponent"/> each frame and uploads it to the renderer
/// as the directional light. Must run before <see cref="MeshRenderSystem"/>.
/// </summary>
public sealed unsafe class LightRenderSystem : ISystem
{
    private readonly Renderer _renderer;

    public LightRenderSystem(Renderer renderer) => _renderer = renderer;

    public void Update(World world, float dt)
    {
        if (LightNode.ComponentId == uint.MaxValue) return;

        var (_, lights) = world.Registry.Query<LightComponent>(LightNode.ComponentId);
        if (lights.Length > 0)
        {
            ref readonly var light = ref lights[0];
            _renderer.SetDirectionalLight(
                light.DirX, light.DirY, light.DirZ,
                light.R, light.G, light.B, light.Intensity);
        }
    }
}
