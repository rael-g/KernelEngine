namespace KernelEngine.Kernel;

/// <summary>
/// ECS storage contract — the engine's component database. Implementations
/// (e.g. flecs, sparse-set) own entity lifecycle, component storage, and
/// queries. The runtime borrows an <see cref="IEcs"/> at construction; the
/// host owns disposal.
/// </summary>
/// <remarks>
/// Current shape is intentionally minimal — disposal only. Component access,
/// entity creation, and queries are routed through the runtime's
/// <c>ke_system_ctx</c> funnel (see <see cref="IRuntime"/>), not through this
/// surface. Future expansions will add managed query helpers here as the
/// surface stabilizes (R5+ Pong migration drives the next set of additions).
/// </remarks>
public interface IEcs : IDisposable
{
}
