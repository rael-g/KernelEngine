using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that acts as an omnidirectional point light source.
/// Adds a <see cref="PointLightComponent"/> to its ECS entity on start.
/// <see cref="LightRenderSystem"/> collects all point light entities each frame.
/// The light position is derived from the node's world-space transform.
/// </summary>
public class PointLightNode : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(EcsRegistry registry)
    {
        if (ComponentId == uint.MaxValue)
            ComponentId = registry.RegisterComponent<PointLightComponent>("PointLightComponent");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>Influence radius. Attenuation reaches zero at this distance.</summary>
    public float Radius { get; init; } = 10f;

    /// <summary>Linear light color.</summary>
    public Vector3 Color { get; init; } = Vector3.One;

    /// <summary>Intensity multiplier.</summary>
    public float Intensity { get; init; } = 1f;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<PointLightComponent>(ComponentId);
        comp = new PointLightComponent
        {
            Radius = Radius,
            R = Color.X, G = Color.Y, B = Color.Z,
            Intensity = Intensity,
        };
    }
}
