using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that acts as an omnidirectional point light source.
/// Adds a <see cref="PointLightComponent"/> to its ECS entity on start.
/// <see cref="LightRenderSystem"/> collects all point light entities each frame.
/// The light position is derived from the node's world-space transform.
/// </summary>
public class PointLight : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(IEcsRegistry registry)
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

    protected override void Start()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<PointLightComponent>(ComponentId);
        comp[0] = new PointLightComponent
        {
            Radius = Radius,
            R = Color.X, G = Color.Y, B = Color.Z,
            Intensity = Intensity,
        };
    }
}
