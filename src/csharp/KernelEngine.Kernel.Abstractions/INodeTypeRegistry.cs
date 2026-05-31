namespace KernelEngine.Kernel;

/// <summary>
/// Language-agnostic node type registry (Tier S — S2).
/// <para>
/// Each binding registers its node classes by string name with factory and property-setter
/// callbacks. The scene loader plugin calls <see cref="TryCreate"/> and
/// <see cref="TrySetProperty"/> to instantiate nodes from a scene file without knowing any
/// language-specific types. Framework registers C# <see cref="Node"/> subclasses here;
/// a future Lua binding would register Lua table factories.
/// </para>
/// </summary>
public interface INodeTypeRegistry
{
    /// <summary>
    /// Registers a node type by string name.
    /// <para>
    /// <paramref name="create"/> receives the ECS entity and name; it must create and bind the
    /// managed node object to that entity. Called once per node instance during scene loading.
    /// </para>
    /// <para>
    /// <paramref name="setProperty"/> receives the entity, property key, and raw value
    /// (primitive, string, array, or TOML table as <c>object?</c>). It is called for each
    /// key/value pair in the scene file's <c>[properties]</c> section. Resource resolution
    /// (e.g. <c>res://</c> paths) is the responsibility of the implementation.
    /// </para>
    /// </summary>
    void Register(string typeName,
        Action<ulong, string>          create,
        Action<ulong, string, object?> setProperty);

    /// <summary>
    /// Looks up the type by name and calls its <c>create</c> callback.
    /// Returns <c>false</c> when no type is registered under <paramref name="typeName"/>.
    /// </summary>
    bool TryCreate(string typeName, ulong entity, string name);

    /// <summary>
    /// Looks up the type by name and calls its <c>setProperty</c> callback.
    /// Returns <c>false</c> when no type is registered under <paramref name="typeName"/>.
    /// No-ops silently for unknown property names (the implementation should ignore them).
    /// </summary>
    bool TrySetProperty(string typeName, ulong entity, string key, object? value);

    /// <summary>
    /// Registers fallback delegates invoked by <see cref="TryCreate"/> and
    /// <see cref="TrySetProperty"/> when no explicit entry matches the type name.
    /// <para>
    /// The C# binding uses this to support any <c>Node</c> subclass without explicit
    /// <see cref="Register"/> calls — the fallback scans loaded assemblies by reflection,
    /// preserving the legacy scene-loader behaviour. A future C++ plugin would not set a
    /// fallback; unregistered types would be hard errors.
    /// </para>
    /// </summary>
    void SetFallback(
        Func<string, ulong, string, bool>           tryCreate,
        Func<string, ulong, string, object?, bool>  trySetProperty);
}
