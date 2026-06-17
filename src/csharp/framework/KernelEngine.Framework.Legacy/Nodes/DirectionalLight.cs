using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A Tree node that acts as a directional light source. Setting <see cref="Direction"/> /
/// <see cref="Color"/> / <see cref="Intensity"/> at any time (init or per-frame in Update)
/// syncs to the underlying ECS slot transparently — game code never touches components.
/// </summary>
public class DirectionalLight : Node
{
    // Backing fields hold values supplied before Start; after Start the ECS slot is authoritative
    // and the property accessors mirror through it. _componentId is cached in Start so live-sync
    // setters don't re-resolve it per access.
    private uint _componentId = uint.MaxValue;
    private Vector3 _direction = Vector3.UnitY;
    private Vector3 _color = Vector3.One;
    private float _intensity = 1f;

    /// <summary>Direction toward the light source (world space).</summary>
    public Vector3 Direction
    {
        get { var s = Slot(); return s.IsEmpty ? _direction : new Vector3(s[0].DirX, s[0].DirY, s[0].DirZ); }
        set { _direction = value; var s = Slot(); if (!s.IsEmpty) { s[0].DirX = value.X; s[0].DirY = value.Y; s[0].DirZ = value.Z; } }
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

    private Span<LightComponent> Slot() =>
        _componentId == uint.MaxValue ? Span<LightComponent>.Empty : GetComponent<LightComponent>(_componentId);

    protected override void Start()
    {
        if (World == null) return;
        _componentId = World.GetOrRegisterComponentId<LightComponent>("LightComponent");
        var comp = AddComponent<LightComponent>(_componentId);
        comp[0] = new LightComponent
        {
            DirX = _direction.X, DirY = _direction.Y, DirZ = _direction.Z,
            R = _color.X, G = _color.Y, B = _color.Z,
            Intensity = _intensity,
        };
    }
}
