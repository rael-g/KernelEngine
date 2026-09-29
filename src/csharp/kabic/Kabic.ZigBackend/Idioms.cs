namespace Kabic.Zig;

using Kabic;

/// <summary>
/// How an ABI symbol is spelled in Zig. Separate from the C# backend's namesake
/// because the two languages disagree about every case it answers: Zig types are
/// PascalCase, its functions are camelCase, its fields and constants are
/// snake_case, and its reserved words are not C#'s.
/// </summary>
public static class Idioms
{
    static readonly Dictionary<string, string> Prim = new()
    {
        ["_Bool"] = "bool", ["bool"] = "bool", ["ke_bool"] = "bool",
        ["uint8_t"] = "u8", ["int8_t"] = "i8",
        ["uint16_t"] = "u16", ["int16_t"] = "i16",
        ["uint32_t"] = "u32", ["int32_t"] = "i32",
        ["uint64_t"] = "u64", ["int64_t"] = "i64",
        ["float"] = "f32", ["double"] = "f64",
        ["size_t"] = "usize", ["void"] = "void", ["char"] = "u8",
        ["int"] = "c_int", ["unsigned"] = "c_uint", ["unsigned int"] = "c_uint",
    };

    /// <summary>
    /// Zig's reserved words. A field or parameter named <c>type</c> is the one that
    /// actually occurs, and it occurs constantly: an id naming a kind is what half
    /// this ABI's slots take.
    /// </summary>
    static readonly HashSet<string> Keywords = ["type", "error", "align", "and", "or", "anytype",
        "asm", "break", "catch", "comptime", "const", "continue", "defer", "else", "enum",
        "errdefer", "export", "extern", "fn", "for", "if", "inline", "noalias", "opaque", "orelse",
        "packed", "pub", "resume", "return", "linksection", "struct", "suspend", "switch", "test",
        "threadlocal", "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while",
        "anyframe", "anyopaque", "callconv", "noinline", "nosuspend", "null", "undefined", "true",
        "false"];

    public static string Pascal(string s) =>
        string.Concat(s.Split('_').Where(p => p.Length > 0)
            .Select(p => char.ToUpperInvariant(p[0]) + p[1..].ToLowerInvariant()));

    public static string Camel(string s)
    {
        var p = Pascal(s);
        return p.Length == 0 ? p : char.ToLowerInvariant(p[0]) + p[1..];
    }

    /// <summary>A Zig identifier, quoted when the name is a keyword.</summary>
    public static string Ident(string s) => Keywords.Contains(s) ? $"@\"{s}\"" : s;

    /// <summary>
    /// The Zig type name for an ABI symbol. Unlike the C# backend this deliberately
    /// ignores <c>TypeNameOverrides</c>: every override in that table exists to
    /// resolve a collision with a C# namespace segment, and a Zig module has no
    /// namespace segments to collide with.
    /// </summary>
    public static string TypeName(string name, Convention convention) =>
        Pascal(convention.StripPrefix(name));

    /// <summary>
    /// An enum member as a Zig field: <c>KE_SCRIPT_REACH_SELF</c> in
    /// <c>ke_script_reach</c> is <c>self</c>. Zig enum members are snake_case and
    /// scoped by the enum, so the prefix the C spelling carried is noise.
    /// </summary>
    public static string EnumMember(string raw, string enumName)
    {
        var parts = enumName.ToUpperInvariant().Split('_');
        for (var keep = 0; keep <= parts.Length; keep++)
        {
            var pre = string.Join('_', parts[..(parts.Length - keep)]) + "_";
            if (!raw.StartsWith(pre)) continue;
            var name = raw[pre.Length..].ToLowerInvariant();
            if (name.Length > 0 && !char.IsDigit(name[0])) return Ident(name);
        }
        return Ident(raw.ToLowerInvariant());
    }

    public static string? Primitive(string cType) => Prim.GetValueOrDefault(Base(cType));

    public static string Base(string cType) =>
        cType.Replace("const ", "").Replace("struct ", "").Replace("enum ", "").Trim();
}
