namespace KernelEngine.Framework;

/// <summary>
/// How many bytes of UTF-8 a node's <see cref="string"/> property stores.
/// </summary>
/// <remarks>
/// A node's component is plain memory every language can read, so a string in it is a
/// fixed buffer rather than a managed reference. The capacity is therefore part of the
/// component's ABI and has to be a number the node's author picks, not one the generator
/// imposes: a path, a title and a shader name are not the same size.
/// <para>
/// Assigning more than fits throws rather than truncating. A silently shortened path is a
/// file that fails to open much later, pointing at nothing that explains it.
/// </para>
/// </remarks>
[AttributeUsage(AttributeTargets.Property)]
public sealed class NodeTextAttribute : Attribute
{
    /// <summary>Capacity in bytes, including the terminator.</summary>
    public int Capacity { get; }

    /// <param name="capacity">Bytes of UTF-8 the property stores, terminator included.</param>
    public NodeTextAttribute(int capacity) => Capacity = capacity;
}
