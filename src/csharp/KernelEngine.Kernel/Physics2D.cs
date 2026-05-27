using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper over a C kernel <c>ke_physics_2d*</c>. Constructed by physics plugins
/// (e.g. <c>AddBox2D()</c>) and registered as <see cref="IPhysics2D"/> for game-code consumption.
/// </summary>
public sealed unsafe class Physics2D : IPhysics2D
{
    private ke_physics_2d* _native;

    public Physics2D(ke_physics_2d* native)
    {
        if (native == null) throw new ArgumentNullException(nameof(native));
        _native = native;
    }

    public void SetGravity(Vector2 gravity)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->set_gravity(_native, gravity.X, gravity.Y);
    }

    public void Step(float deltaTime)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->step(_native, deltaTime);
    }

    public BodyHandle2D CreateBody(BodyType2D type, Vector2 position)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        uint id;
        var res = _native->create_body(_native, (ke_body_type_2d)(int)type, position.X, position.Y, &id).ToManaged();
        return res == KernelResult.Ok ? new BodyHandle2D(id) : BodyHandle2D.None;
    }

    public void DestroyBody(BodyHandle2D body)
    {
        if (_native == null || !body.IsValid) return;
        _native->destroy_body(_native, body.Value);
    }

    public void AddBoxFixture(BodyHandle2D body, Vector2 halfExtents, float density = 1f, float friction = 0.3f, float restitution = 0f)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        if (!body.IsValid) return;
        _native->add_box_fixture(_native, body.Value, halfExtents.X, halfExtents.Y, density, friction, restitution);
    }

    public void AddCircleFixture(BodyHandle2D body, float radius, float density = 1f, float friction = 0.3f, float restitution = 0f)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        if (!body.IsValid) return;
        _native->add_circle_fixture(_native, body.Value, radius, density, friction, restitution);
    }

    public BodyState2D GetBodyState(BodyHandle2D body)
    {
        if (_native == null || !body.IsValid) return default;
        ke_body_state_2d state;
        _native->get_body_state(_native, body.Value, &state);
        return new BodyState2D(
            Position:        new Vector2(state.x, state.y),
            Angle:           state.angle,
            Velocity:        new Vector2(state.velocity_x, state.velocity_y),
            AngularVelocity: state.angular_velocity);
    }

    public void SetBodyPosition(BodyHandle2D body, Vector2 position, float angle = 0f)
    {
        if (_native == null || !body.IsValid) return;
        _native->set_body_position(_native, body.Value, position.X, position.Y, angle);
    }

    public void SetBodyVelocity(BodyHandle2D body, Vector2 velocity)
    {
        if (_native == null || !body.IsValid) return;
        _native->set_body_velocity(_native, body.Value, velocity.X, velocity.Y);
    }

    public void ApplyImpulse(BodyHandle2D body, Vector2 impulse)
    {
        if (_native == null || !body.IsValid) return;
        _native->apply_impulse(_native, body.Value, impulse.X, impulse.Y);
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
