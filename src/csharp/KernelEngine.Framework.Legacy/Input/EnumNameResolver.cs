using System.Diagnostics.CodeAnalysis;
using System.Runtime.CompilerServices;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Single resolution point for enum-name &lt;-&gt; enum-value lookups used by the action layer's
/// file loader. Isolated here so the AOT story can change without touching the loader.
/// </summary>
/// <remarks>
/// <para>
/// <b>Today:</b> backed by <see cref="Enum.TryParse{TEnum}(string, bool, out TEnum)"/> and
/// <see cref="Enum.GetValues{TEnum}"/>. Both are AOT-safe on .NET 8+ — no IL emit, no
/// <c>Reflection.Emit</c> — but the .NET trimmer warns on <see cref="Enum.GetValues{TEnum}"/>
/// for trimming-sensitive code (which we suppress; the enum metadata is preserved as long as
/// the game's enum type is referenced from gameplay code, which it always is).
/// </para>
/// <para>
/// <b>Tomorrow (when AOT publishing actually matters):</b> swap this class for a source-generator
/// that emits a <c>switch</c> on enum names per game enum. Callers don't change.
/// </para>
/// </remarks>
public static class EnumNameResolver<TEnum> where TEnum : struct, Enum
{
    /// <summary>
    /// Parses <paramref name="name"/> case-sensitively into a value of <typeparamref name="TEnum"/>.
    /// Throws <see cref="ArgumentException"/> with a list of valid names when not found.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public static TEnum Parse(string name)
    {
        if (Enum.TryParse<TEnum>(name, ignoreCase: false, out var v)) return v;
        throw new ArgumentException(
            $"'{name}' is not a valid {typeof(TEnum).Name}. Valid names: {string.Join(", ", Enum.GetNames<TEnum>())}.");
    }

    /// <summary>All values declared in <typeparamref name="TEnum"/>, with their string names.</summary>
    [UnconditionalSuppressMessage("Trimming", "IL2090",
        Justification = "TEnum comes from gameplay code and is always referenced; trimmer keeps its metadata.")]
    public static IEnumerable<(string Name, TEnum Value)> All()
    {
        var values = Enum.GetValues<TEnum>();
        var names  = Enum.GetNames<TEnum>();
        for (int i = 0; i < values.Length; i++)
            yield return (names[i], values[i]);
    }
}
