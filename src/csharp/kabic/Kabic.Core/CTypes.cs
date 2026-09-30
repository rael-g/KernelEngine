namespace Kabic;

using System.Text.RegularExpressions;

/// Operations on a raw C type string (`"const ke_log_event *"`) that have
/// nothing to do with any target language's naming or type-mapping
/// conventions — every backend needs to know whether a type is a pointer and
/// what it points to, none of them decide it differently.
public static class CTypes
{
    public static bool IsPointer(string cType) => cType.TrimEnd().EndsWith('*');

    /// The type with its qualifiers and declaration spacing removed
    /// (`"const struct ke_system_ctx *"` -> `"ke_system_ctx*"`), which is the
    /// spelling a cast needs. A header writes a pointer type however reads best
    /// at the declaration; a generated cast has to name it one way.
    public static string Normalize(string cType)
    {
        var t = cType.Replace("const ", "").Replace("struct ", "").Trim();
        return t.TrimEnd('*', ' ') + new string('*', t.Count(c => c == '*'));
    }

    /// The element type and extent of a fixed-size array declarator
    /// (`"float[16]"` -> `("float", 16)`, `"void *[8]"` -> `("void *", 8)`), or
    /// null when the type declares a single value. The extent is part of the type
    /// in C and in every language that mirrors the layout, so a backend that does
    /// not ask this question emits the C declarator verbatim and the element type
    /// never reaches its primitive mapping.
    public static (string Element, int Extent)? FixedArray(string cType)
    {
        var m = Regex.Match(cType.Trim(), @"^(.+?)\s*\[(\d+)\]$");
        return m.Success ? (m.Groups[1].Value.Trim(), int.Parse(m.Groups[2].Value)) : null;
    }

    /// Strips exactly ONE level of pointer-ness (`"ke_texture_data **"` ->
    /// `"ke_texture_data *"`, not `"ke_texture_data"`) — a caller wanting the
    /// fully-dereferenced base type calls this as many times as there are
    /// `*`s, or goes through a type mapper that recurses itself (see
    /// CSharpBackend.CsType). `TrimEnd('*', ' ')` here would strip every
    /// trailing `*` at once, silently over-dereferencing a `T**` out-param
    /// (an allocated-elsewhere pointer, e.g. ke_texture_data**) down to the
    /// bare value type `T` instead of the single-pointer `T*` it actually is.
    public static string Deref(string cType)
    {
        var t = cType.Trim().Replace("const ", "").Replace("struct ", "").TrimEnd();
        return t.EndsWith('*') ? t[..^1].TrimEnd() : t;
    }
}
