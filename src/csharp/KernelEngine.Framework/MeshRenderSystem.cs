using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Iterates all ECS entities with a <see cref="MeshComponent"/> and records
/// draw commands into the frame packet for asynchronous submission.
/// </summary>
public sealed unsafe class MeshRenderSystem : ISystem
{
    private readonly Renderer _renderer;

    /// <param name="renderer">The renderer (used for handle lookups if needed).</param>
    public MeshRenderSystem(Renderer renderer) => _renderer = renderer;

    public void Update(World world, float dt, FramePacket? packet = null)
    {
        if (MeshNode.ComponentId == uint.MaxValue || packet == null) return;

        var (entities, data) = world.Registry.Query<MeshComponent>(MeshNode.ComponentId);
        for (int i = 0; i < entities.Length; i++)
        {
            var tc = world.Registry.GetComponent<TransformComponent>(entities[i], world.TransformComponentId);
            if (tc != null)
            {
                // Record instead of submitting immediately
                packet.AddDrawCommand(data[i].MeshHandle, data[i].MaterialHandle, tc->WorldMatrix);
            }
        }
    }
}
