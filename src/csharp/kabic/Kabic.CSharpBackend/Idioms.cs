
namespace Kabic.CSharp;

using Kabic;
using System.Text.RegularExpressions;

public static class Idioms
{
    static readonly Dictionary<string, string> Prim = new()
    {
        ["_Bool"] = "bool", ["uint32_t"] = "uint", ["int32_t"] = "int",
        ["uint64_t"] = "ulong", ["int64_t"] = "long", ["float"] = "float", ["double"] = "double",
        ["void"] = "void", ["size_t"] = "nuint",
        ["uint16_t"] = "ushort", ["int16_t"] = "short", ["uint8_t"] = "byte", ["int8_t"] = "sbyte",
        ["char"] = "sbyte",
    };

    static readonly HashSet<string> CsKeywords = ["event", "base", "params", "object", "string", "lock",
        "ref", "out", "in", "checked", "default", "null", "delegate", "fixed", "unsafe", "class",
        "struct", "interface", "namespace", "using", "static", "public", "private", "internal",
        "new", "this", "value", "operator", "is", "as", "sizeof", "typeof", "switch", "case",
        "for", "foreach", "while", "do", "if", "else", "return", "break", "continue", "goto",
        "try", "catch", "finally", "throw", "int", "uint", "long", "ulong", "short", "ushort",
        "byte", "sbyte", "float", "double", "decimal", "bool", "char", "void", "enum", "const"];

    public static string Pascal(string s)
    {
        if (s.Length == 0) return s;
        return string.Concat(s.Split('_').Where(p => p.Length > 0)
            .Select(p => char.ToUpperInvariant(p[0]) + p[1..].ToLowerInvariant()));
    }

    public static string Camel(string s)
    {
        var p = Pascal(s);
        return p.Length == 0 ? p : char.ToLowerInvariant(p[0]) + p[1..];
    }

    /// A C# identifier for a parameter name, escaping reserved words (`event` is
    /// the recurring one — ke_log_event's own parameter is literally named that).
    public static string Ident(string s)
    {
        var c = Camel(s);
        return CsKeywords.Contains(c) ? "@" + c : c;
    }

    /// Strips the longest `ke_`/domain prefix that still leaves a valid,
    /// non-digit-leading C# identifier. `KE_MOUSE_BUTTON_1` would otherwise
    /// become the invalid `1`, so it backs off to `Button1`.
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

    /// The C# type name for an ABI symbol: strips the ABI's own symbol prefix
    /// (which carries no meaning in a namespaced language) and PascalCases the rest.
    public static string TypeName(string name, Convention convention) =>
        convention.TypeNameOverrides.TryGetValue(name, out var overridden)
            ? overridden
            : Pascal(convention.StripPrefix(name));

    public static string CsPrimitive(string cType, Convention convention)
    {
        var t = cType.Trim();
        if (t == convention.ByteBoolType) return "bool";
        if (t is "void *" or "void*") return "nint";
        return Prim.GetValueOrDefault(t, t);
    }

    /// A C pointer type used verbatim in generated C# (e.g. a factory param
    /// pointing into another domain, `struct ke_logger *`): strips `struct `/
    /// `const ` and normalizes spacing so it reads as a C# pointer type
    /// (`ke_logger*`). The caller is responsible for bringing the target
    /// type's namespace into scope (see --using).
    public static string CsForeignType(string cType, Convention convention)
    {
        var t = cType.Trim().Replace("const ", "").Replace("struct ", "");
        if (t == convention.ByteBoolType) return "bool";
        return Prim.TryGetValue(t.TrimEnd('*', ' '), out var prim) && !t.Contains('*')
            ? prim
            : t.TrimEnd('*', ' ') + (t.Contains('*') ? "*" : "");
    }
}
