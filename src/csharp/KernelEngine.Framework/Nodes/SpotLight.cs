using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that acts as a cone-shaped spot light source.
/// Adds a <see cref="SpotLightComponent"/> to its ECS entity on start.
/// <see cref="LightRenderSystem"/> collects all spot light entities each frame.
/// The light position is derived from the node's world-space transform.
/// </summary>
public class SpotLight : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    public static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(IEcsRegistry registry)
    {
        if (ComponentId == uint.MaxValue)
            ComponentId = registry.RegisterComponent<SpotLightComponent>("SpotLightComponent");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>Direction the cone points toward (world space). Default: pointing down.</summary>
    public Vector3 Direction { get; init; } = -Vector3.UnitY;

    /// <summary>Attenuation range. Intensity reaches zero at this distance.</summary>
    public float Range { get; init; } = 15f;

    /// <summary>Inner cone half-angle in degrees (full intensity inside).</summary>
    public float InnerAngleDegrees { get; init; } = 15f;

    /// <summary>Outer cone half-angle in degrees (zero intensity outside).</summary>
    public float OuterAngleDegrees { get; init; } = 30f;

    /// <summary>Linear light color.</summary>
    public Vector3 Color { get; init; } = Vector3.One;

    /// <summary>Intensity multiplier.</summary>
    public float Intensity { get; init; } = 1f;

    protected override void Start()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<SpotLightComponent>(ComponentId);
        comp[0] = new SpotLightComponent
        {
            DirX = Direction.X, DirY = Direction.Y, DirZ = Direction.Z,
            InnerAngle = InnerAngleDegrees * MathF.PI / 180f,
            OuterAngle = OuterAngleDegrees * MathF.PI / 180f,
            Range = Range,
            R = Color.X, G = Color.Y, B = Color.Z,
            Intensity = Intensity,
        };
    }
}
