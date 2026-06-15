using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Point light node — emits light in all directions from this entity's world position.
/// </summary>
public class PointLight : Node
{
    private PointLightComponent _state = new()
    {
        Color     = Vector3.One,
        Intensity = 1f,
        Radius    = 10f,
    };

    public Vector3 Color     { get => _state.Color;     set { _state.Color     = value; WriteIfBound(); } }
    public float   Intensity { get => _state.Intensity; set { _state.Intensity = value; WriteIfBound(); } }
    public float   Radius    { get => _state.Radius;    set { _state.Radius    = value; WriteIfBound(); } }

    private void WriteIfBound() { if (IsBound) NodeWorld!.Set(Entity, _state); }

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.Set(Entity, _state);
}
