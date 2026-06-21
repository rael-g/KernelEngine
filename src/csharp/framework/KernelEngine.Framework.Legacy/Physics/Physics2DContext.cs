using KernelEngine.Physics;


namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Thread-local accessor exposing the active 2D physics world + framework system to
/// <see cref="CollisionBody2D"/> during its <c>Start</c>. Mirrors the
/// <see cref="InputContext"/> pattern — set once at the top of each sim tick, cleared at the bottom.
/// Engine-internal.
/// </summary>
internal static class Physics2DContext
{
    [ThreadStatic]
    private static IPhysics2D? s_physics;
    [ThreadStatic]
    private static Physics2DSystem? s_system;

    public static IPhysics2D? PhysicsOrNull => s_physics;
    public static Physics2DSystem? SystemOrNull => s_system;

    /// <summary>The active 2D physics backend. Throws when no physics plugin is registered.</summary>
    public static IPhysics2D Physics =>
        s_physics ?? throw new InvalidOperationException(
            "Physics2DContext.Physics is unavailable. Add a 2D physics plugin (e.g. .AddBox2D(...)).");

    /// <summary>The framework system tracking body→node mappings. Throws when no physics plugin is registered.</summary>
    public static Physics2DSystem System =>
        s_system ?? throw new InvalidOperationException(
            "Physics2DContext.System is unavailable. Add a 2D physics plugin (e.g. .AddBox2D(...)).");

    public static void Set(IPhysics2D? physics, Physics2DSystem? system)
    {
        s_physics = physics;
        s_system  = system;
    }
}
