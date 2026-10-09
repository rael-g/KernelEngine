namespace Kabic;

using System.Text.RegularExpressions;

/// <summary>
/// Operations on a raw C type string (<c>"const ke_log_event *"</c>) that have
/// nothing to do with any target language's naming or type-mapping
/// conventions — every backend needs to know whether a type is a pointer and
/// what it points to, none of them decide it differently.
/// </summary>
public static class CTypes
{
    /// <summary>Whether the C type is a pointer, which holds when its last non-space character is a star.</summary>
    /// <param name="cType">The C spelling of a type, such as <c>"const ke_log_event *"</c>.</param>
    /// <returns><see langword="true"/> when the type ends in a star.</returns>
    public static bool IsPointer(string cType) => cType.TrimEnd().EndsWith('*');

    /// <summary>
    /// The type with its qualifiers and declaration spacing removed
    /// (<c>"const struct ke_system_ctx *"</c> -&gt; <c>"ke_system_ctx*"</c>), which is the
    /// spelling a cast needs. A header writes a pointer type however reads best
    /// at the declaration; a generated cast has to name it one way.
    /// </summary>
    public static string Normalize(string cType)
    {
        var t = cType.Replace("const ", "").Replace("struct ", "").Trim();
        return t.TrimEnd('*', ' ') + new string('*', t.Count(c => c == '*'));
    }

    /// <summary>
    /// The element type and extent of a fixed-size array declarator
    /// (<c>"float[16]"</c> -&gt; <c>("float", 16)</c>, <c>"void *[8]"</c> -&gt; <c>("void *", 8)</c>), or
    /// null when the type declares a single value. The extent is part of the type
    /// in C and in every language that mirrors the layout, so a backend that does
    /// not ask this question emits the C declarator verbatim and the element type
    /// never reaches its primitive mapping.
    /// </summary>
    public static (string Element, int Extent)? FixedArray(string cType)
    {
        var m = Regex.Match(cType.Trim(), @"^(.+?)\s*\[(\d+)\]$");
        return m.Success ? (m.Groups[1].Value.Trim(), int.Parse(m.Groups[2].Value)) : null;
    }

    /// <summary>
    /// Strips exactly ONE level of pointer-ness (<c>"ke_texture_data **"</c> -&gt;
    /// <c>"ke_texture_data *"</c>, not <c>"ke_texture_data"</c>) — a caller wanting the
    /// fully-dereferenced base type calls this as many times as there are
    /// <c>*</c>s, or goes through a type mapper that recurses itself (see
    /// CSharpBackend.CsType). <c>TrimEnd('*', ' ')</c> here would strip every
    /// trailing <c>*</c> at once, silently over-dereferencing a <c>T**</c> out-param
    /// (an allocated-elsewhere pointer, e.g. ke_texture_data**) down to the
    /// bare value type <c>T</c> instead of the single-pointer <c>T*</c> it actually is.
    /// </summary>
    public static string Deref(string cType)
    {
        var t = cType.Trim().Replace("const ", "").Replace("struct ", "").TrimEnd();
        return t.EndsWith('*') ? t[..^1].TrimEnd() : t;
    }
}
