using System.Numerics;
using KernelEngine;

namespace KernelEngine.Framework;

/// <summary>
/// A scene node that acts as a directional light source. Adds a <see cref="LightComponent"/>
/// to its ECS entity on start. <see cref="LightRenderSystem"/> reads all light entities each frame.
/// </summary>
public class LightNode : Node
{
    // ── ECS registration ──────────────────────────────────────────────────────

    internal static uint ComponentId { get; private set; } = uint.MaxValue;

    internal static void Initialize(EcsRegistry registry)
    {
        if (ComponentId == uint.MaxValue)
            ComponentId = registry.RegisterComponent<LightComponent>("LightComponent");
    }

    // ── Per-instance ──────────────────────────────────────────────────────────

    /// <summary>Direction toward the light source (world space). Default: sun directly above.</summary>
    public Vector3 Direction { get; init; } = Vector3.UnitY;

    /// <summary>Linear light color.</summary>
    public Vector3 Color { get; init; } = Vector3.One;

    /// <summary>Intensity multiplier.</summary>
    public float Intensity { get; init; } = 1f;

    protected override void OnStart()
    {
        if (ComponentId == uint.MaxValue) return;
        ref var comp = ref AddComponent<LightComponent>(ComponentId);
        comp = new LightComponent
        {
            DirX = Direction.X, DirY = Direction.Y, DirZ = Direction.Z,
            R = Color.X, G = Color.Y, B = Color.Z,
            Intensity = Intensity,
        };
    }
}
