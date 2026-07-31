namespace Kabic;

/// Operations on a raw C type string (`"const ke_log_event *"`) that have
/// nothing to do with any target language's naming or type-mapping
/// conventions — every backend needs to know whether a type is a pointer and
/// what it points to, none of them decide it differently.
public static class CTypes
{
    public static bool IsPointer(string cType) => cType.TrimEnd().EndsWith('*');

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
