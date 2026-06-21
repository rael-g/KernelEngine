using KernelEngine.Physics;


namespace KernelEngine.Framework;

/// <summary>
/// Implemented by nodes that own a 2D physics body.
/// <see cref="CollisionShape2D"/> walks up the parent chain to find this
/// interface and attaches its fixture to the owning body.
/// </summary>
public interface IPhysicsBody2D
{
    /// <summary>The physics body owned by this node.</summary>
    BodyHandle2D PhysicsBody { get; }
}
