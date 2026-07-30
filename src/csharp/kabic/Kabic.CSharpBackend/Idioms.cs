// kabic's C# naming and type-mapping conventions (ScriptingArchitectureV3
// §6.2): the only place PascalCase/camelCase, C# reserved-word escaping, and
// the C-type -> C# primitive table live. Pure decisions about how C# reads;
// nothing here decides what a slot MEANS (that's Kabic.Core's Classifier).

namespace Kabic.CSharp;

using Kabic;
using System.Text.RegularExpressions;


// =============================================================================
// -- C#-only naming and type-mapping conventions -----------------------------
// =============================================================================

public static class Idioms
{
    static readonly Dictionary<string, string> Prim = new()
    {
        ["_Bool"] = "bool", ["ke_bool"] = "bool", ["uint32_t"] = "uint", ["int32_t"] = "int",
        ["uint64_t"] = "ulong", ["int64_t"] = "long", ["float"] = "float", ["double"] = "double",
        ["void"] = "void", ["size_t"] = "nuint",
    };

    static readonly HashSet<string> CsKeywords = ["event", "base", "params", "object", "string", "lock",
        "ref", "out", "in", "checked", "default", "null", "delegate"];

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
        // enumName is already ke_snake_case; its natural macro prefix is its own
        // uppercase form, e.g. ke_mouse_button -> KE_MOUSE_BUTTON_.
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

    public static string StripPrefix(string name) => Pascal(name.StartsWith("ke_") ? name[3..] : name);

    public static string CsPrimitive(string cType)
    {
        var t = cType.Trim();
        // An opaque `void *` return (a platform handle: HWND, X11 Window, ...)
        // is `nint` by convention here, not a raw unsafe pointer — matches the
        // hand-written precedent this replaces (`(nint)get_native_handle(...)`).
        if (t is "void *" or "void*") return "nint";
        return Prim.GetValueOrDefault(t, t);
    }

    /// A C pointer type used verbatim in generated C# (e.g. a factory param
    /// pointing into another domain, `struct ke_logger *`): strips `struct `/
    /// `const ` and normalizes spacing so it reads as a C# pointer type
    /// (`ke_logger*`). The caller is responsible for bringing the target
    /// type's namespace into scope (see --using).
    public static string CsForeignType(string cType)
    {
        var t = cType.Trim().Replace("const ", "").Replace("struct ", "");
        return Prim.TryGetValue(t.TrimEnd('*', ' '), out var prim) && !t.Contains('*')
            ? prim
            : t.TrimEnd('*', ' ') + (t.Contains('*') ? "*" : "");
    }
}
