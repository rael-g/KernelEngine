using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Scene-wide ambient light node. First entity in the scene with this
/// component wins; if a <see cref="DirectionalLight"/> also carries its own
/// Ambient field, whichever contributor runs last writes the final state on
/// the packet (LightContributor runs after AmbientContributor, so the
/// directional's value wins when both exist).
/// </summary>
public class AmbientLight : Node
{
    private AmbientLightComponent _state = new() { Color = new(0.05f, 0.05f, 0.05f) };

    public Vector3 Color
    {
        get => _state.Color;
        set { _state.Color = value; if (IsBound) Tree!.SetAmbientLight(Entity, _state); }
    }

    protected internal override void OnBind(Tree tree) => tree.SetAmbientLight(Entity, _state);
}
