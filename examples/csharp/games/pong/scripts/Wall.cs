using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Physics;

namespace Pong;

/// <summary>
/// Top / bottom static wall — Box2D static body. The visual is a Sprite2D
/// child declared in Wall.scene; this script owns only the physics fixture.
/// </summary>
public sealed class Wall : Node
{
    private readonly IPhysics2D _physics;

    private BodyHandle2D _body;

    public Wall(IPhysics2D physics) => _physics = physics;

    protected override void OnBind(NodeWorld nodeWorld)
    {
        var pos = new Vector2(LocalTransform.Position.X, LocalTransform.Position.Y);
        _body = _physics.CreateBody(BodyType2D.Static, pos);
        _physics.AddBoxFixture(_body, new Vector2(8.0f, 0.25f), restitution: 1f);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);
}
