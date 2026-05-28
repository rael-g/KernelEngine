using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Drives the 2D physics world with a fixed-step accumulator and syncs body poses back into
/// <see cref="Node.LocalTransform"/> at the end of each frame. Auto-registered by
/// <see cref="Application"/> when an <see cref="IPhysics2D"/> backend is in DI; game code never
/// instantiates or steps physics directly.
/// </summary>
/// <remarks>
/// <para>
/// Steps at a fixed <c>1/60s</c> rate regardless of frame rate; the accumulator absorbs render
/// jitter (deterministic simulation, see chapter 24 §5). Visible high-refresh interpolation is a
/// later concern.
/// </para>
/// <para>
/// Collision events (<c>OnCollisionEnter</c>/<c>Exit</c>) are not yet wired — chapter 24 step 5.
/// MVP delivers pose authority and stepping ownership only.
/// </para>
/// </remarks>
public sealed class Physics2DSystem : ISystem
{
    private readonly IPhysics2D _physics;
    private readonly Dictionary<BodyHandle2D, CollisionBody2D> _bodyToNode = new();
    private float _accumulator;

    /// <summary>Fixed simulation timestep (seconds). Configurable knob lands when needed.</summary>
    public const float FixedTimestep = 1f / 60f;

    public Physics2DSystem(IPhysics2D physics)
    {
        _physics = physics;
    }

    public void Update(IWorld world, float deltaTime, IFramePacket? packet, IInputReader? input)
    {
        _accumulator += deltaTime;
        // Cap to avoid the "spiral of death" if a frame stalls — at most ~8 sub-steps per frame.
        int safety = 8;
        while (_accumulator >= FixedTimestep && safety-- > 0)
        {
            _physics.Step(FixedTimestep);
            _accumulator -= FixedTimestep;
        }
        if (safety <= 0) _accumulator = 0f;

        SyncBodiesToTransforms();
    }

    internal void Register(CollisionBody2D body)
    {
        if (body.Body.IsValid) _bodyToNode[body.Body] = body;
    }

    internal void Unregister(CollisionBody2D body)
    {
        if (body.Body.IsValid) _bodyToNode.Remove(body.Body);
    }

    private void SyncBodiesToTransforms()
    {
        foreach (var (_, node) in _bodyToNode)
        {
            var state = _physics.GetBodyState(node.Body);
            var lt = node.LocalTransform;
            node.LocalTransform = lt with {
                Position = new Vector3(state.Position.X, state.Position.Y, lt.Position.Z),
                Rotation = Quaternion.CreateFromAxisAngle(Vector3.UnitZ, state.Angle),
            };
        }
    }
}
