namespace KernelEngine.Framework;

/// <summary>
/// Maps the string names used in <c>.scene</c> files to managed <see cref="Type"/>s
/// that <see cref="SceneLoader"/> instantiates. Built at startup via
/// <c>services.AddNodeType&lt;T&gt;()</c>.
/// </summary>
public sealed class NodeTypeRegistry
{
    private readonly Dictionary<string, Type> _byName = new(StringComparer.Ordinal);

    public NodeTypeRegistry Register<T>(string? name = null) where T : Node
    {
        _byName[name ?? typeof(T).FullName!] = typeof(T);
        _byName.TryAdd(typeof(T).Name, typeof(T));
        return this;
    }

    public Type Resolve(string name)
    {
        if (!_byName.TryGetValue(name, out var t))
            throw new InvalidOperationException(
                $"Scene references node type '{name}' but it is not registered. " +
                $"Call services.AddNodeType<{name}>() during startup.");
        return t;
    }
}
