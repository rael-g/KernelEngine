using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// A Tree node that acts as an omnidirectional point light source. Setting
/// <see cref="Radius"/> / <see cref="Color"/> / <see cref="Intensity"/> at any time
/// (init or per-frame in Update) syncs to the underlying ECS slot transparently —
/// game code never touches components.
/// </summary>
public class PointLight : Node
{
    private uint _componentId = uint.MaxValue;
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
        _componentId == uint.MaxValue ? Span<PointLightComponent>.Empty : GetComponent<PointLightComponent>(_componentId);

    protected override void Start()
    {
        if (World == null) return;
        _componentId = World.GetOrRegisterComponentId<PointLightComponent>("PointLightComponent");
        var comp = AddComponent<PointLightComponent>(_componentId);
        comp[0] = new PointLightComponent
        {
            Radius = _radius,
            R = _color.X, G = _color.Y, B = _color.Z,
            Intensity = _intensity,
        };
    }
}
