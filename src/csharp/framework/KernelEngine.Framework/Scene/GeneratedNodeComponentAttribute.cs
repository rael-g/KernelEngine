namespace KernelEngine.Framework;

/// <summary>
/// Marks a node class whose partial properties are backed by an existing native component
/// struct, registered under the given name. A class without it is game-authored and
/// <c>KernelEngine.SourceGenerators</c> synthesizes a backing struct for it. Applied more than
/// once, the class owns that many components, each with its own backing state and component id,
/// and every partial property routes to the one whose struct declares its field. The attribute
/// is read from the class's own declaration only, not from its base classes.
/// </summary>
[AttributeUsage(AttributeTargets.Class, AllowMultiple = true)]
public sealed class GeneratedNodeComponentAttribute(Type backingType, string componentName) : Attribute
{
    /// <summary>The native struct type holding this node's data.</summary>
    public Type BackingType { get; } = backingType;

    /// <summary>The name this component is registered under at runtime.</summary>
    public string ComponentName { get; } = componentName;
}

/// <summary>
/// Names the backing struct field a node's partial property reads and writes, and optionally the
/// component that declares it.
/// </summary>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NativeFieldAttribute(string name) : Attribute
{
    /// <summary>The backing struct's field name.</summary>
    public string Name { get; } = name;

    /// <summary>
    /// Which of the node's components declares this field. Left null, the field name alone
    /// resolves the component, and a name declared by two of them is an error.
    /// </summary>
    public Type? Component { get; init; }
}
