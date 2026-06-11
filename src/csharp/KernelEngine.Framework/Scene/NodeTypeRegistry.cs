namespace KernelEngine.Framework;

/// <summary>
/// Maps the string names used in <c>.scene</c> files (e.g. <c>"Camera"</c>,
/// <c>"Pong.Paddle"</c>) to managed <see cref="Type"/>s that the
/// <see cref="SceneLoader"/> instantiates. Built up at startup via
/// <c>services.AddNodeType&lt;T&gt;()</c> for every type the loader should
/// recognize — including the framework's own built-ins (<see cref="Camera"/>,
/// <see cref="DirectionalLight"/>, …) and game-specific scripts.
/// </summary>
public sealed class NodeTypeRegistry
{
    private readonly Dictionary<string, Type> _byName = new(StringComparer.Ordinal);

    /// <summary>
    /// Registers <typeparamref name="T"/> under <paramref name="name"/>; when
    /// <paramref name="name"/> is null, falls back to the type's full name
    /// (<see cref="Type.FullName"/>) so it matches <c>"Pong.Paddle"</c>-style
    /// scene references out of the box.
    /// </summary>
    public NodeTypeRegistry Register<T>(string? name = null) where T : Node
    {
        _byName[name ?? typeof(T).FullName!] = typeof(T);
        // Also key by short name so authors can write `"Paddle"` instead of
        // `"Pong.Paddle"` when there's no ambiguity. Last writer wins on
        // collisions — explicit names supersede inferred shortcuts.
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
