using System.Numerics;
using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Top / bottom static wall — visual quad + Box2D static body. Half-extents
/// come from the bound transform's Scale (which the scene file sets).
/// </summary>
public sealed class Wall : MeshRenderer
{
    private readonly IPhysics2D    _physics;
    private readonly PongResources _resources;

    private BodyHandle2D _body;

    public Wall(IPhysics2D physics, PongResources resources)
    {
        _physics   = physics;
        _resources = resources;
    }

    protected override void OnBind(Tree tree)
    {
        MaterialHandle = _resources.WallMat;
        base.OnBind(tree);

        var t      = LocalTransform;
        var pos    = new Vector2(t.Position.X, t.Position.Y);
        var halfEx = new Vector2(t.Scale.X * 0.5f, t.Scale.Y * 0.5f);
        _body  = _physics.CreateBody(BodyType2D.Static, pos);
        _physics.AddBoxFixture(_body, halfEx, restitution: 1f);
    }

    protected override void OnUnbind() => _physics.DestroyBody(_body);
}
