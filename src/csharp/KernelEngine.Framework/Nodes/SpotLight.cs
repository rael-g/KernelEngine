using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A Tree node that acts as a cone-shaped spot light source. Setting any of
/// <see cref="Direction"/> / <see cref="Range"/> / <see cref="InnerAngleDegrees"/> /
/// <see cref="OuterAngleDegrees"/> / <see cref="Color"/> / <see cref="Intensity"/>
/// at any time (init or per-frame in Update) syncs to the underlying ECS slot
/// transparently — game code never touches components.
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

    private Vector3 _direction = -Vector3.UnitY;
    private float _range = 15f;
    private float _innerAngleDegrees = 15f;
    private float _outerAngleDegrees = 30f;
    private Vector3 _color = Vector3.One;
    private float _intensity = 1f;

    /// <summary>Direction the cone points toward (world space). Default: pointing down.</summary>
    public Vector3 Direction
    {
        get { var s = Slot(); return s.IsEmpty ? _direction : new Vector3(s[0].DirX, s[0].DirY, s[0].DirZ); }
        set { _direction = value; var s = Slot(); if (!s.IsEmpty) { s[0].DirX = value.X; s[0].DirY = value.Y; s[0].DirZ = value.Z; } }
    }

    /// <summary>Attenuation range. Intensity reaches zero at this distance.</summary>
    public float Range
    {
        get { var s = Slot(); return s.IsEmpty ? _range : s[0].Range; }
        set { _range = value; var s = Slot(); if (!s.IsEmpty) s[0].Range = value; }
    }

    /// <summary>Inner cone half-angle in degrees (full intensity inside).</summary>
    public float InnerAngleDegrees
    {
        get { var s = Slot(); return s.IsEmpty ? _innerAngleDegrees : s[0].InnerAngle * 180f / MathF.PI; }
        set { _innerAngleDegrees = value; var s = Slot(); if (!s.IsEmpty) s[0].InnerAngle = value * MathF.PI / 180f; }
    }

    /// <summary>Outer cone half-angle in degrees (zero intensity outside).</summary>
    public float OuterAngleDegrees
    {
        get { var s = Slot(); return s.IsEmpty ? _outerAngleDegrees : s[0].OuterAngle * 180f / MathF.PI; }
        set { _outerAngleDegrees = value; var s = Slot(); if (!s.IsEmpty) s[0].OuterAngle = value * MathF.PI / 180f; }
    }

    /// <summary>Linear light color.</summary>
    public Vector3 Color
    {
        get { var s = Slot(); return s.IsEmpty ? _color : new Vector3(s[0].R, s[0].G, s[0].B); }
        set { _color = value; var s = Slot(); if (!s.IsEmpty) { s[0].R = value.X; s[0].G = value.Y; s[0].B = value.Z; } }
    }

    /// <summary>Intensity multiplier.</summary>
    public float Intensity
    {
        get { var s = Slot(); return s.IsEmpty ? _intensity : s[0].Intensity; }
        set { _intensity = value; var s = Slot(); if (!s.IsEmpty) s[0].Intensity = value; }
    }

    private Span<SpotLightComponent> Slot() =>
        ComponentId == uint.MaxValue ? Span<SpotLightComponent>.Empty : GetComponent<SpotLightComponent>(ComponentId);

    protected override void Start()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<SpotLightComponent>(ComponentId);
        comp[0] = new SpotLightComponent
        {
            DirX = _direction.X, DirY = _direction.Y, DirZ = _direction.Z,
            InnerAngle = _innerAngleDegrees * MathF.PI / 180f,
            OuterAngle = _outerAngleDegrees * MathF.PI / 180f,
            Range = _range,
            R = _color.X, G = _color.Y, B = _color.Z,
            Intensity = _intensity,
        };
    }
}
