using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine;

/// <summary>
/// Managed snapshot of a native <c>ke_error_type</c> node, including its parent chain.
/// Copied at the boundary — holds no native pointer, so it's safe to surface to game code.
/// </summary>
/// <remarks>
/// Error types form a hierarchy via <see cref="Parent"/> (e.g. <c>KE_FLECS_NULL_ERROR</c>
/// descends from <c>KE_NULL_ERROR</c>). <see cref="Is"/> walks that chain so a caller can
/// match either the specific type or any ancestor — mirroring the native <c>ke_error_is()</c>.
/// </remarks>
public sealed class KernelErrorType
{
    /// <summary>The type's name, e.g. <c>"KE_ERROR_NOT_FOUND"</c>.</summary>
    public string Name { get; }

    /// <summary>The parent type this one descends from, or <see langword="null"/> at the root.</summary>
    public KernelErrorType? Parent { get; }

    internal KernelErrorType(string name, KernelErrorType? parent)
    {
        Name = name;
        Parent = parent;
    }

    /// <summary>
    /// True if this type is named <paramref name="name"/> or descends (transitively) from a type
    /// with that name. Walks up the <see cref="Parent"/> chain, mirroring native <c>ke_error_is()</c>.
    /// </summary>
    public bool Is(string name)
    {
        for (KernelErrorType? t = this; t is not null; t = t.Parent)
            if (t.Name == name)
                return true;
        return false;
    }

    /// <summary>
    /// Materializes a managed copy of a native <c>ke_error_type*</c> and its full parent chain.
    /// Boundary helper — the result holds no native pointer.
    /// </summary>
    public static unsafe KernelErrorType? FromNative(ke_error_type* type)
    {
        if (type is null)
            return null;

        string name = type->name is not null
            ? Marshal.PtrToStringUTF8((nint)type->name) ?? "?"
            : "?";
        return new KernelErrorType(name, FromNative(type->parent));
    }

    /// <inheritdoc/>
    public override string ToString() => Name;
}
