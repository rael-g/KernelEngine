
namespace Kabic.CSharp;

using System.Text.RegularExpressions;

using Kabic;

/// <summary>
/// Maps the spellings of a C ABI to the spellings a C# file uses: names to PascalCase and
/// camelCase, reserved words escaped, enum members and type names stripped of their prefixes, and C
/// scalar types to their C# types.
/// </summary>
public static class Idioms
{
    static readonly Dictionary<string, string> Prim = new()
    {
        ["_Bool"] = "bool",
        ["uint32_t"] = "uint",
        ["int32_t"] = "int",
        ["uint64_t"] = "ulong",
        ["int64_t"] = "long",
        ["float"] = "float",
        ["double"] = "double",
        ["void"] = "void",
        ["size_t"] = "nuint",
        ["uint16_t"] = "ushort",
        ["int16_t"] = "short",
        ["uint8_t"] = "byte",
        ["int8_t"] = "sbyte",
        ["char"] = "sbyte",
    };

    static readonly HashSet<string> CsKeywords = ["event", "base", "params", "object", "string", "lock",
        "ref", "out", "in", "checked", "default", "null", "delegate", "fixed", "unsafe", "class",
        "struct", "interface", "namespace", "using", "static", "public", "private", "internal",
        "new", "this", "value", "operator", "is", "as", "sizeof", "typeof", "switch", "case",
        "for", "foreach", "while", "do", "if", "else", "return", "break", "continue", "goto",
        "try", "catch", "finally", "throw", "int", "uint", "long", "ulong", "short", "ushort",
        "byte", "sbyte", "float", "double", "decimal", "bool", "char", "void", "enum", "const"];

    /// <summary>
    /// Converts a snake_case name to PascalCase. Returns <paramref name="s"/> unchanged when it is
    /// empty.
    /// </summary>
    public static string Pascal(string s)
    {
        if (s.Length == 0) return s;
        return string.Concat(s.Split('_').Where(p => p.Length > 0)
            .Select(p => char.ToUpperInvariant(p[0]) + p[1..].ToLowerInvariant()));
    }

    /// <summary>
    /// Converts a snake_case name to camelCase. Returns an empty string when
    /// <paramref name="s"/> holds no words.
    /// </summary>
    public static string Camel(string s)
    {
        var p = Pascal(s);
        return p.Length == 0 ? p : char.ToLowerInvariant(p[0]) + p[1..];
    }

    /// <summary>
    /// A C# identifier for <paramref name="s"/>: its camelCase form, prefixed with <c>@</c> when
    /// that form is one of the C# keywords kabic escapes.
    /// </summary>
    public static string Ident(string s)
    {
        var c = Camel(s);
        return CsKeywords.Contains(c) ? "@" + c : c;
    }

    /// <summary>
    /// Strips the longest `ke_`/domain prefix that still leaves a valid,
    /// non-digit-leading C# identifier. `KE_MOUSE_BUTTON_1` would otherwise
    /// become the invalid `1`, so it backs off to `Button1`.
    /// </summary>
    public static string EnumMember(string raw, string enumName)
    {
        var prefix = enumName.ToUpperInvariant() + "_";
        var parts = prefix.TrimEnd('_').Split('_');
        for (var keep = 0; keep <= parts.Length; keep++)
        {
            var pre = string.Join('_', parts[..(parts.Length - keep)]) + "_";
            if (raw.StartsWith(pre))
            {
                var name = Pascal(raw[pre.Length..]);
                if (name.Length > 0 && !char.IsDigit(name[0])) return name;
            }
        }
        return Pascal(raw);
    }

    /// <summary>
    /// The C# type name for an ABI symbol: strips the ABI's own symbol prefix
    /// (which carries no meaning in a namespaced language) and PascalCases the rest.
    /// </summary>
    public static string TypeName(string name, Convention convention) =>
        convention.TypeNameOverrides.TryGetValue(name, out var overridden)
            ? overridden
            : Pascal(convention.StripPrefix(name));

    /// <summary>
    /// The C# spelling of a C scalar type name: the convention's byte-boolean type is <c>bool</c>,
    /// a void pointer is <c>nint</c>, and any other trimmed name is looked up in the primitive
    /// table and returned unchanged when the table does not hold it.
    /// </summary>
    public static string CsPrimitive(string cType, Convention convention)
    {
        var t = cType.Trim();
        if (t is "void *" or "void*") return "nint";
        return Prim.GetValueOrDefault(t, t);
    }

    /// <summary>
    /// The C# spelling of a C type that may be a pointer: strips <c>const</c> and <c>struct</c>,
    /// and maps a primitive name without a pointer
    /// through the primitive table. Any other name is returned without its trailing pointer marks,
    /// with one <c>*</c> appended when the type is a pointer.
    /// </summary>
    public static string CsForeignType(string cType, Convention convention)
    {
        var t = cType.Trim().Replace("const ", "").Replace("struct ", "");
        return Prim.TryGetValue(t.TrimEnd('*', ' '), out var prim) && !t.Contains('*')
            ? prim
            : t.TrimEnd('*', ' ') + (t.Contains('*') ? "*" : "");
    }
}
