using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Spot light node — emits a cone of light from this entity's world position.
/// </summary>
public class SpotLight : Node
{
    private SpotLightComponent _state = new()
    {
        Direction     = -Vector3.UnitY,
        Color         = Vector3.One,
        Intensity     = 1f,
        Range         = 20f,
        InnerAngleDeg = 25f,
        OuterAngleDeg = 35f,
    };

    public Vector3 Direction     { get => _state.Direction;     set { _state.Direction     = value; WriteIfBound(); } }
    public Vector3 Color         { get => _state.Color;         set { _state.Color         = value; WriteIfBound(); } }
    public float   Intensity     { get => _state.Intensity;     set { _state.Intensity     = value; WriteIfBound(); } }
    public float   Range         { get => _state.Range;         set { _state.Range         = value; WriteIfBound(); } }
    public float   InnerAngleDeg { get => _state.InnerAngleDeg; set { _state.InnerAngleDeg = value; WriteIfBound(); } }
    public float   OuterAngleDeg { get => _state.OuterAngleDeg; set { _state.OuterAngleDeg = value; WriteIfBound(); } }

    private void WriteIfBound() { if (IsBound) Tree!.Set(Entity, _state); }

    protected internal override void OnBind(Tree tree) => tree.Set(Entity, _state);
}
