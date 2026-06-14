using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Scene-wide ambient light node. First entity with this component wins.
/// </summary>
public class AmbientLight : Node
{
    private AmbientLightComponent _state = new() { Color = new(0.05f, 0.05f, 0.05f) };

    public Vector3 Color
    {
        get => _state.Color;
        set { _state.Color = value; if (IsBound) Tree!.Set(Entity, _state); }
    }

    protected internal override void OnBind(Tree tree) => tree.Set(Entity, _state);
}
