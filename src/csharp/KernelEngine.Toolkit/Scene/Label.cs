using System.Numerics;

namespace KernelEngine.Framework;

/// <summary>
/// Screen-space text node. Position is computed each frame as
/// <c>Anchor × backbufferSize + Offset</c>, then pivoted by <see cref="Anchor"/>
/// applied to the measured text size.
/// </summary>
public class Label : Node
{
    public string  Text   { get; set; } = string.Empty;
    public Font?   Font   { get; set; }
    public Vector4 Color  { get; set; } = Vector4.One;

    /// <summary>Anchor in normalized [0..1] of the backbuffer. (0,0) = top-left, (1,1) = bottom-right.</summary>
    public Vector2 Anchor { get; set; } = Vector2.Zero;

    /// <summary>Pixel offset applied AFTER anchor positioning.</summary>
    public Vector2 Offset { get; set; } = Vector2.Zero;

    protected internal override void OnBind(NodeWorld nodeWorld) => nodeWorld.RegisterLabel(this);
}
