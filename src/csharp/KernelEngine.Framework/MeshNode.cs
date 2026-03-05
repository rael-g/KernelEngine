using System.Numerics;
using KernelEngine;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that renders a colored quad via the ECS mesh render system.
/// Add to a scene with <c>scene.AddNode(new MeshNode { Color = … }, "name")</c>.
/// </summary>
public class MeshNode : Node
{
    // ── ECS registration (shared across all MeshNode instances) ──────────────

    internal static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(EcsRegistry registry)
    {
        if (ComponentId == uint.MaxValue)
            ComponentId = registry.RegisterComponent<MeshComponent>("MeshComponent");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>The RGBA color of this mesh. Set before adding to the scene.</summary>
    public Vector4 Color { get; init; } = Vector4.One;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<MeshComponent>(ComponentId);
        comp = new MeshComponent { R = Color.X, G = Color.Y, B = Color.Z, A = Color.W };
    }
}
