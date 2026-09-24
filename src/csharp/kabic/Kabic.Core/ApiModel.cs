
namespace Kabic;

public record ApiParam(string? Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

public record ApiSlot(string Name, string Returns, IReadOnlyList<string> Tags, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

public record ApiEnumValue(string Name, string RawValue, bool IsInt, string? Doc);

public record ApiEnum(string Name, string? Doc, IReadOnlyList<ApiEnumValue> Values)
{
    /// <summary>The tags the enum's own doc block declared.</summary>
    public IReadOnlyList<string> Tags { get; init; } = [];

    /// <summary>Whether the enum carries <paramref name="tag"/>, with or without a value.</summary>
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));

    /// <summary>
    /// Whether this enum came from a header this domain composes against rather than
    /// describes (<c>--compose</c>). Present because a composed struct's field can be
    /// typed by it and a backend must name that type; the owning domain still emits it.
    /// </summary>
    public bool External { get; init; }
}

public record ApiField(string Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

public record ApiStruct(string Name, string? Doc, IReadOnlyList<string> Tags, IReadOnlyList<ApiField> Fields, IReadOnlyList<ApiSlot> Slots)
{
    /// <summary>
    /// Whether the struct holds any function-pointer slot. This is a shape
    /// question, not a role one: a parameter bag also carries the callback it
    /// registers, so a caller deciding whether to emit an interface must
    /// additionally consult the naming convention (see <c>Convention.IsParamsType</c>).
    /// </summary>
    public bool IsVtable => Slots.Count > 0;

    /// <summary>
    /// Whether this struct came from a header this domain composes against rather than
    /// describes (<c>--compose</c>). It is present so a node in this domain can reference
    /// a bundle another domain owns and have its component set resolved; the domain still
    /// emits nothing for it, because the owning domain already does.
    /// </summary>
    public bool External { get; init; }

    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

public record ApiFunction(string Name, string Returns, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params);

public class ApiModel
{
    public List<ApiEnum> Enums { get; } = [];
    public List<ApiStruct> Structs { get; } = [];
    public List<ApiFunction> Functions { get; } = [];

    /// <summary>
    /// Typedefs that resolve to a plain C primitive (<c>ke_entity</c> -> <c>uint64_t</c>),
    /// which every backend must see through — a language with no typedef concept has
    /// nothing to map <c>ke_entity</c> onto otherwise. Typedefs naming a struct or enum
    /// are absent: those are real types the description already carries.
    /// </summary>
    public Dictionary<string, string> TypeAliases { get; } = [];

    /// <summary>Resolves a type through <see cref="TypeAliases"/> until it is no longer an alias.</summary>
    public string ResolveAlias(string type)
    {
        var t = type.Trim();
        for (var i = 0; i < 8 && TypeAliases.TryGetValue(t, out var next); i++) t = next;
        return t;
    }
}

public static class ApiReader
{
    public static ApiModel Read(System.Text.Json.Nodes.JsonObject root)
    {
        var m = new ApiModel();
        foreach (var eRaw in root["enums"]!.AsArray())
        {
            var e = eRaw!.AsObject();
            m.Enums.Add(new ApiEnum(Str(e, "name")!, Str(e, "doc"),
                e["values"]!.AsArray().Select(vRaw =>
                {
                    var v = vRaw!.AsObject();
                    var isInt = v["value"] is System.Text.Json.Nodes.JsonValue jv && jv.TryGetValue<long>(out _);
                    return new ApiEnumValue(Str(v, "name")!,
                        isInt ? v["value"]!.GetValue<long>().ToString() : Str(v, "value")!,
                        isInt, Str(v, "doc"));
                }).ToList())
            {
                External = e["external"]?.GetValue<bool>() == true,
                Tags = e["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [],
            });
        }

        void ReadStructLike(System.Text.Json.Nodes.JsonObject o, bool vtable)
        {
            var slots = vtable
                ? o["slots"]!.AsArray().Select(s => ReadSlot(s!.AsObject())).ToList()
                : [];
            var fields = o["fields"]!.AsArray()
                .Select(fRaw =>
                {
                    var f = fRaw!.AsObject();
                    return new ApiField(Str(f, "name")!, Str(f, "type")!,
                        f["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [], Str(f, "doc"));
                })
                .ToList();
            var tags = o["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [];
            m.Structs.Add(new ApiStruct(Str(o, "name")!, Str(o, "doc"), tags, fields, slots)
            {
                External = o["external"]?.GetValue<bool>() == true,
            });
        }

        foreach (var s in root["structs"]!.AsArray()) ReadStructLike(s!.AsObject(), vtable: false);
        foreach (var v in root["vtables"]!.AsArray()) ReadStructLike(v!.AsObject(), vtable: true);

        if (root["type_aliases"] is System.Text.Json.Nodes.JsonObject aliases)
            foreach (var kv in aliases)
                m.TypeAliases[kv.Key] = kv.Value!.GetValue<string>();

        foreach (var f in root["functions"]!.AsArray())
        {
            var o = f!.AsObject();
            m.Functions.Add(new ApiFunction(Str(o, "name")!, Str(o, "returns")!, Str(o, "doc"), Str(o, "return_doc"),
                o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList()));
        }
        return m;
    }

    static ApiSlot ReadSlot(System.Text.Json.Nodes.JsonObject o) => new(Str(o, "name")!, Str(o, "returns")!,
        o["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [], Str(o, "doc"),
        Str(o, "return_doc"), o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList());

    static ApiParam ReadParam(System.Text.Json.Nodes.JsonObject o) => new(Str(o, "name"), Str(o, "type")!,
        o["tags"]!.AsArray().Select(t => t!.GetValue<string>()).ToList(), Str(o, "doc"));

    static string? Str(System.Text.Json.Nodes.JsonObject o, string key) => o[key]?.GetValue<string>();
}
