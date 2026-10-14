namespace KernelEngine.Framework;

/// <summary>
/// One component a node type's behavior reaches, and whether it writes to it.
/// </summary>
/// <param name="Name">The name the component is registered under at runtime.</param>
/// <param name="Writes">
/// Whether the behavior can store to it. True whenever that cannot be ruled out.
/// </param>
/// <param name="Owned">
/// Whether the node's own entity carries it, as opposed to reaching it through a borrow of
/// another node.
/// </param>
public readonly record struct NodeComponentUse(string Name, bool Writes, bool Owned);
