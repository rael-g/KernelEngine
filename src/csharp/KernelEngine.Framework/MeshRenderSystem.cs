using KernelEngine;

namespace KernelEngine.Framework;

/// <summary>
/// Iterates all ECS entities with a <see cref="MeshComponent"/> and submits
/// colored quad draw calls using their TransformComponent world matrix.
/// </summary>
public sealed unsafe class MeshRenderSystem : ISystem
{
    private readonly Renderer _renderer;

    /// <param name="renderer">The renderer to submit draw calls to.</param>
    public MeshRenderSystem(Renderer renderer) => _renderer = renderer;

    public void Update(World world, float dt)
    {
        if (MeshNode.ComponentId == uint.MaxValue) return;

        var (entities, data) = world.Registry.Query<MeshComponent>(MeshNode.ComponentId);
        for (int i = 0; i < entities.Length; i++)
        {
            var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
            if (tc != null)
                _renderer.SubmitColored(tc->WorldMatrix, data[i].R, data[i].G, data[i].B, data[i].A);
        }
    }
}
