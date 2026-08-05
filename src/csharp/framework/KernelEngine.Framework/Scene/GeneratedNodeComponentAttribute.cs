namespace KernelEngine.Framework;

/// <summary>
/// Marks a <c>kabic</c>-generated node type: its partial properties are backed by an
/// existing native component struct, resolved by the registered name a domain header
/// already gives it — never a synthesized struct or a newly registered name. Absence of
/// this attribute is what tells <c>KernelEngine.SourceGenerators</c> a node type is
/// game-authored and needs its own backing struct synthesized instead.
/// </summary>
[AttributeUsage(AttributeTargets.Class)]
public sealed class GeneratedNodeComponentAttribute(Type backingType, string componentName) : Attribute
{
    /// <summary>The native struct type holding this node's data.</summary>
    public Type BackingType { get; } = backingType;

    /// <summary>The name this component is registered under at runtime.</summary>
    public string ComponentName { get; } = componentName;
}

/// <summary>
/// Names the backing struct field a <see cref="GeneratedNodeComponentAttribute"/> node's
/// partial property reads and writes, when it differs from the property name — always,
/// since the native struct spells fields in the ABI's own casing and, for a
/// <c>System.Numerics.VectorN</c> property, as a fixed-size array rather than a single field.
/// </summary>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NativeFieldAttribute(string name) : Attribute
{
    /// <summary>The backing struct's field name.</summary>
    public string Name { get; } = name;
}
