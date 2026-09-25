namespace KernelEngine.Runtime;

/// <summary>
/// One component a system touches, and how. The scheduler groups systems into
/// parallel waves by comparing these: two systems conflict when they name the
/// same component and at least one writes it, and conflicting systems are placed
/// in different waves. A system that declares nothing conflicts with nothing and
/// is therefore free to run concurrently with everything.
/// </summary>
public readonly record struct ComponentAccess(uint Cid, RuntimeAccess Access)
{
    /// <summary>Declares a read of <paramref name="cid"/>.</summary>
    public static ComponentAccess Read(uint cid) => new(cid, RuntimeAccess.Read);

    /// <summary>Declares a write of <paramref name="cid"/>.</summary>
    public static ComponentAccess Write(uint cid) => new(cid, RuntimeAccess.Write);
}

/// <summary>
/// A tuple of components matched together, resolved into archetype segments before
/// the system's wave runs. The system body reads the result positionally, by the
/// index this query was declared at.
/// </summary>
public readonly record struct QueryDecl(params ComponentAccess[] Terms)
{
    /// <summary>
    /// Terms one query may carry, fixed by <c>KE_QUERY_MAX_TERMS</c>. A caller
    /// composing a query from a set it does not control checks this first —
    /// exceeding it is refused at registration, not silently truncated.
    /// </summary>
    public const int MaxTerms = 8;
}

/// <summary>
/// Scheduler-centric runtime that owns the simulation world, dispatches systems
/// across the thread pool, and drives the frame loop. Mirrors the <c>ke_runtime</c>
/// C ABI, which is the contract this interface is derived from — where the two
/// disagree, the header is right.
/// </summary>
public interface IRuntime : IDisposable
{
    /// <summary>
    /// Registers a module. The runtime calls <paramref name="onLoad"/> during
    /// the Startup phase in dependency order, and <paramref name="onUnload"/> as the
    /// runtime is disposed, in reverse registration order.
    /// </summary>
    ulong RegisterModule(string name, Action<IRuntime> onLoad, Action<IRuntime>? onUnload = null);

    /// <summary>
    /// Registers a system in the given scheduler <paramref name="phase"/>.
    /// </summary>
    /// <param name="queries">
    /// Component tuples the system reads through, in declaration order. The runtime
    /// resolves them into segments before the wave and derives scheduling access
    /// from their terms.
    /// </param>
    /// <param name="accessList">
    /// Components the system touches that no query term covers, folded into the
    /// same derived set so the wave builder still orders on them: ordering-only
    /// tags, and entity-keyed reads.
    /// </param>
    /// <param name="pinnedThread">
    /// 0 = any worker (load-balanced, default). 1..N = pin to that specific
    /// scheduler worker, for thread-affine work (GPU calls on the render worker).
    /// </param>
    /// <remarks>
    /// Declaring nothing is not "no opinion" — it tells the scheduler this system
    /// conflicts with nobody, so it may run concurrently with every other system in
    /// its phase. Anything touching component storage should say so.
    /// </remarks>
    /// <param name="perEntity">
    /// The body's work on one entity is independent of every other entity it visits,
    /// letting the runtime run it as concurrent slices of the same set. Each call then
    /// handles the share <c>SystemCtx.Slice</c> reports. A body that reaches an entity
    /// other than the one it is visiting, or touches state shared across the set, must
    /// leave this false.
    /// </param>
    ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, float> execute,
                          IReadOnlyList<QueryDecl>? queries = null,
                          IReadOnlyList<ComponentAccess>? accessList = null,
                          uint pinnedThread = 0,
                          bool perEntity = false);

    /// <summary>
    /// Registers a system whose callback also receives the native system-context
    /// pointer (as an <see cref="nint"/>) for the current tick. The context is the
    /// only safe channel for structural world mutation (node create/destroy) from
    /// inside a running system — it defers the change to the wave barrier. The
    /// pointer is opaque to managed code; forward it to APIs that accept one.
    /// </summary>
    /// <param name="perEntity">
    /// The body's work on one entity is independent of every other entity it visits,
    /// letting the runtime run it as concurrent slices of the same set. Each call then
    /// handles the share <c>SystemCtx.Slice</c> reports. A body that reaches an entity
    /// other than the one it is visiting, or touches state shared across the set, must
    /// leave this false.
    /// </param>
    ulong RegisterSystem(string name, RuntimePhase phase, Action<IRuntime, nint, float> execute,
                          IReadOnlyList<QueryDecl>? queries = null,
                          IReadOnlyList<ComponentAccess>? accessList = null,
                          uint pinnedThread = 0,
                          bool perEntity = false);

    /// <summary>Drives one frame: PreUpdate → FixedUpdate×N → Update → PostUpdate, then dispatches Render.</summary>
    void Tick(float dt);

    /// <summary>
    /// Blocks until any render phase dispatched by a previous <see cref="Tick"/>
    /// has finished. Tick() dispatches render asynchronously and returns before
    /// it completes; call this before tearing down render-owned native
    /// resources (GPU device, swapchain surface) or the still-running render
    /// phase races the teardown. A no-op if nothing is pending.
    /// </summary>
    void Flush();
}
