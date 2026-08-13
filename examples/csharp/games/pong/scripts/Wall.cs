using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// Top / bottom static wall. Composes <see cref="Body2D"/> and owns nothing else —
/// the collider is a CollisionShape2D child and the visual a Sprite2D child, both
/// declared in Wall.scene.
/// </summary>
public sealed partial class Wall : Body2D
{
    public Wall() => Type = BodyType2D.Static;
}
