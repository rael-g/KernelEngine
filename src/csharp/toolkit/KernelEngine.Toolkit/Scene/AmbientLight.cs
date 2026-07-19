using System.Numerics;
using KernelEngine.Render;

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
        set { _state.Color = value; if (IsBound) NodeWorld!.Set(Entity, _state); }
    }

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.Set(Entity, _state);
}
