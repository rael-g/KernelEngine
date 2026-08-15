namespace KernelEngine.Framework;

/// <summary>
/// How many bytes of UTF-8 a node's <see cref="string"/> property stores.
/// </summary>
/// <remarks>Assigning more than fits throws rather than truncating.</remarks>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NodeTextAttribute : Attribute
{
    /// <summary>Capacity in bytes, including the terminator.</summary>
    public int Capacity { get; }

    /// <param name="capacity">Bytes of UTF-8 the property stores, terminator included.</param>
    public NodeTextAttribute(int capacity) => Capacity = capacity;
}
