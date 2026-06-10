namespace KernelEngine.Kernel;

/// <summary>
/// Scheduler-centric runtime that owns the simulation world, dispatches systems
/// across the thread pool, and drives the frame loop. See
/// <c>docs/RuntimeArchitectureV2.md</c> §3 for the C ABI contract this mirrors.
/// </summary>
/// <remarks>
/// First implementation: <c>FlecsRuntime</c> (wraps the <c>ke_runtime_flecs</c>
/// plugin which wraps the flecs ECS). Subsequent impls (custom, entt-backed)
/// satisfy the same interface; consumers depend on this contract, never on the
/// concrete impl.
/// </remarks>
public interface IRuntime : IDisposable
{
    /// <summary>
    /// Registers a module. The runtime calls <paramref name="onLoad"/> during
    /// the Startup phase in dependency order. Spike subset: <paramref name="onLoad"/>
    /// is invoked synchronously at registration time; dependency ordering and
    /// the explicit Startup phase land in R2+.
    /// </summary>
    ulong RegisterModule(string name, Action<IRuntime> onLoad);

    /// <summary>
    /// Registers a system in the given scheduler <paramref name="phase"/>.
    /// <paramref name="execute"/> receives the runtime and the frame delta.
    /// Read/write set declarations come with R3+ once consumers need them for
    /// parallel scheduling.
    /// </summary>
    ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute);

    /// <summary>Drives one frame: PreUpdate → Update → PostUpdate (Extract / FixedUpdate land in R2+).</summary>
    void Tick(float dt);
}

/// <summary>Mirrors <c>ke_phase</c>. Order matches the C enum so casts are safe.</summary>
public enum RuntimePhase
{
    Startup     = 0,
    PreUpdate   = 1,
    FixedUpdate = 2,
    Update      = 3,
    PostUpdate  = 4,
    Extract     = 5,
    Shutdown    = 6,
}
