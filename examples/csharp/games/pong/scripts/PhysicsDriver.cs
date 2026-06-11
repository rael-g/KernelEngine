using KernelEngine.Framework;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Steps Box2D once per frame. Registered LAST in the scene so all the body
/// nodes (paddles, ball) get a chance to set their velocities from input
/// before the simulation advances.
/// </summary>
public sealed class PhysicsDriver : Node
{
    private readonly IPhysics2D _physics;

    public PhysicsDriver(IPhysics2D physics) { _physics = physics; }

    protected override void OnBind(Tree tree) { }

    protected override void OnUpdate(in View view) => _physics.Step(view.DeltaTime);
}
