namespace KernelEngine.Framework;

/// <summary>
/// One component a node type's behavior reaches, and whether it writes to it. The
/// pair is what the host turns into the system's declared access — a name alone
/// would have to assume writing, which orders the system against everything else
/// touching that component and costs the parallelism the declaration exists to buy.
/// </summary>
/// <param name="Name">The name the component is registered under at runtime.</param>
/// <param name="Writes">
/// Whether the behavior can store to it. True whenever that cannot be ruled out:
/// under-declaring a write is a data race, so anything unproven says true.
/// </param>
/// <param name="Owned">
/// Whether the node's own entity carries it, as opposed to reaching it through a
/// borrow of another node. Only the owned set describes what the entity is, so only
/// it can become a query — asking the ECS for a component the node itself never
/// carries would match nothing and silently stop the behavior from running.
/// </param>
public readonly record struct NodeComponentUse(string Name, bool Writes, bool Owned);
