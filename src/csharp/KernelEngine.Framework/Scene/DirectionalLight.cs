using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Directional light node + ambient. Init properties feed the per-frame light
/// state the renderer consumes. (Ambient is folded into this node for now to
/// keep the example surface small; a dedicated <c>AmbientLight</c> node lands
/// when an example needs them decoupled.)
/// </summary>
public sealed class DirectionalLight : Node
{
    public Vector3 Direction { get; set; } = new(0.2f, 1f, 0.5f);
    public Vector3 Color     { get; set; } = Vector3.One;
    public float   Intensity { get; set; } = 1f;
    public Vector3 Ambient   { get; set; } = new(0.2f, 0.2f, 0.2f);

    protected internal override void OnBind(Tree tree)
    {
        tree.SetDirectionalLight(Entity, new DirectionalLightComponent
        {
            Direction = Direction,
            Color     = Color,
            Intensity = Intensity,
            Ambient   = Ambient,
        });
    }
}
