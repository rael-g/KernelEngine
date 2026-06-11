using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Directional light node + ambient. Init properties feed the per-frame light
/// state the renderer consumes. (Ambient is folded into this node for now to
/// keep the example surface small; a dedicated <c>AmbientLight</c> node lands
/// when an example needs them decoupled.)
/// </summary>
public class DirectionalLight : Node
{
    // _state is the source of truth for the node's writable light data. Pre-bind
    // it is populated by object-initializer property setters; post-bind every
    // setter writes the full struct through to the ECS component so render-side
    // contributors see the change on the next contribute pass.
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

    private void WriteIfBound() { if (IsBound) Tree!.SetDirectionalLight(Entity, _state); }

    protected internal override void OnBind(Tree tree) => tree.SetDirectionalLight(Entity, _state);
}
