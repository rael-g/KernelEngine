namespace KernelEngine.Framework;

/// <summary>
/// Marks a <c>kabic</c>-generated node type: its partial properties are backed by an
/// existing native component struct, resolved by the registered name a domain header
/// already gives it — never a synthesized struct or a newly registered name. Absence of
/// this attribute is what tells <c>KernelEngine.SourceGenerators</c> a node type is
/// game-authored and needs its own backing struct synthesized instead.
/// <para>
/// Applied more than once, the node type composes that many components: each gets its own
/// backing state and component id, and every partial property routes to the one whose
/// struct declares its field. A node type is a component SET, so composing two of them
/// composes their sets — it is never a base class relationship.
/// </para>
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

    /// <summary>
    /// Which of the node's components declares this field, when more than one of them
    /// spells the same field name. Left null, the field name alone resolves the component;
    /// a name declared by two of them is an error the generator refuses rather than guesses.
    /// </summary>
    public Type? Component { get; init; }
}

/// <summary>
/// Marks a <see cref="GeneratedNodeComponentAttribute"/> node's partial property as backed
/// by the ENTIRE native struct, bit-cast, rather than one field of it — the property type
/// must be layout-identical to the backing struct (a hand-written managed mirror, the same
/// relationship <c>TransformComponent</c> already has to <c>ke_transform_component</c>).
/// Mutually exclusive with <see cref="NativeFieldAttribute"/> for the same component: that
/// component is exposed by one <c>[NativeWhole]</c> property and no per-field ones, since the
/// whole struct is a single atomic read/write (e.g. setting position/rotation/scale together
/// in one native call, not three), the same guarantee a hand-written whole-struct property
/// already gave callers.
/// </summary>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NativeWholeAttribute : Attribute
{
    /// <summary>
    /// Which of the node's components this property is the whole of, when the node composes
    /// more than one. Left null, the node's single component is used.
    /// </summary>
    public Type? Component { get; init; }
}
