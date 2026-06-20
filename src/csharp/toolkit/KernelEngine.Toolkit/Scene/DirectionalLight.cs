using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Directional light node. Init properties feed the per-frame light state the renderer consumes.
/// </summary>
public class DirectionalLight : Node
{
    private DirectionalLightComponent _state = new()
    {
        Direction = new(0.2f, 1f, 0.5f),
        Color     = Vector3.One,
        Intensity = 1f,
        Ambient   = new(0.2f, 0.2f, 0.2f),
    };

    public Vector3 Direction { get => _state.Direction; set { _state.Direction = value; WriteIfBound(); } }
    public Vector3 Color     { get => _state.Color;     set { _state.Color     = value; WriteIfBound(); } }
    public float   Intensity { get => _state.Intensity; set { _state.Intensity = value; WriteIfBound(); } }
    public Vector3 Ambient   { get => _state.Ambient;   set { _state.Ambient   = value; WriteIfBound(); } }

    private void WriteIfBound() { if (IsBound) NodeWorld!.Set(Entity, _state); }

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.Set(Entity, _state);
}
