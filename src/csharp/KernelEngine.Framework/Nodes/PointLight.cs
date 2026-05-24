using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// A Tree node that acts as an omnidirectional point light source. Setting
/// <see cref="Radius"/> / <see cref="Color"/> / <see cref="Intensity"/> at any time
/// (init or per-frame in Update) syncs to the underlying ECS slot transparently —
/// game code never touches components.
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

    // Backing fields hold values supplied before Start; after Start the ECS slot is authoritative
    // and the property accessors mirror through it.
    private float _radius = 10f;
    private Vector3 _color = Vector3.One;
    private float _intensity = 1f;

    /// <summary>Influence radius. Attenuation reaches zero at this distance.</summary>
    public float Radius
    {
        get { var s = Slot(); return s.IsEmpty ? _radius : s[0].Radius; }
        set { _radius = value; var s = Slot(); if (!s.IsEmpty) s[0].Radius = value; }
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

    private Span<PointLightComponent> Slot() =>
        ComponentId == uint.MaxValue ? Span<PointLightComponent>.Empty : GetComponent<PointLightComponent>(ComponentId);

    protected override void Start()
    {
        if (ComponentId == uint.MaxValue) return;
        var comp = AddComponent<PointLightComponent>(ComponentId);
        comp[0] = new PointLightComponent
        {
            Radius = _radius,
            R = _color.X, G = _color.Y, B = _color.Z,
            Intensity = _intensity,
        };
    }
}
