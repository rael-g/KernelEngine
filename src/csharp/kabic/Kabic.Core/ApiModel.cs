
namespace Kabic;

/// <summary>A parameter of a function, a slot or a callback lane, with the tags its declaration carries.</summary>
public record ApiParam(string? Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    /// <summary>Whether the parameter carries <paramref name="tag"/>, with or without a value.</summary>
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));

    /// <summary>The text after the colon of the first tag named <paramref name="tag"/>, or null.</summary>
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

/// <summary>A function-pointer slot of a vtable, with its return, parameters and tags as declared.</summary>
public record ApiSlot(string Name, string Returns, IReadOnlyList<string> Tags, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    /// <summary>
    /// The tags the slot's <c>@return</c> block declared. A return is not a parameter and
    /// cannot carry one of its own, so what the returned value means beyond its type —
    /// that it is the front of a sequence, say — has nowhere else to be stated.
    /// </summary>
    public IReadOnlyList<string> ReturnTags { get; init; } = [];

    /// <summary>
    /// The type of the parameter the slot hangs off, which is not always the struct that
    /// declares it: an owner wrapper's <c>destroy</c> takes the value the wrapper holds,
    /// not the wrapper. A backend that declares the ABI itself instead of importing the
    /// header has no other source for it, and a declaration naming the wrong pointer type
    /// still compiles.
    /// </summary>
    public string? Receiver { get; init; }

    /// <summary>Whether the slot carries <paramref name="tag"/>, with or without a value.</summary>
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));

    /// <summary>The text after the colon of the first tag named <paramref name="tag"/>, or null.</summary>
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];

    /// <summary>The value of <paramref name="tag"/> on the slot's return, or null.</summary>
    public string? ReturnTagValue(string tag) =>
        ReturnTags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

/// <summary>One named value of an enum, with its value as text and whether that value is an integer.</summary>
public record ApiEnumValue(string Name, string RawValue, bool IsInt, string? Doc);

/// <summary>An enum the header declares, with its values in the order the description lists them.</summary>
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

/// <summary>A field of a struct, with its type, tags and doc as declared.</summary>
public record ApiField(string Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    /// <summary>Whether the field carries <paramref name="tag"/>, with or without a value.</summary>
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));

    /// <summary>The text after the colon of the first tag named <paramref name="tag"/>, or null.</summary>
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

/// <summary>A struct or vtable the header declares: its fields, and the slots of a vtable.</summary>
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

    /// <summary>Whether the struct carries <paramref name="tag"/>, with or without a value.</summary>
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));

    /// <summary>The text after the colon of the first tag named <paramref name="tag"/>, or null.</summary>
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

/// <summary>An exported global the header declares (<c>extern const T NAME;</c>).</summary>
public record ApiVariable(string Name, string Type, string? Doc);

/// <summary>A function the header declares, with its return type and its parameters.</summary>
public record ApiFunction(string Name, string Returns, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    /// <summary>The tags the function's <c>@return</c> block declared.</summary>
    public IReadOnlyList<string> ReturnTags { get; init; } = [];
}

/// <summary>
/// A function-pointer typedef described lane by lane. Which lane carries the caller's
/// opaque context, which carries a utf8 string, and which is an outbound error channel
/// is a contract the typedef's own parameter documentation declares; the string
/// spelling of the type carries none of it, and a backend that has to guess gets it
/// wrong. Lanes keep the order the prototype declares, so an index identifies one.
/// </summary>
public record ApiCallback(string Name, string Returns, string? Doc, IReadOnlyList<ApiParam> Lanes);

/// <summary>
/// The declarations one header description lists, kept in the order they were read: enums,
/// structs and vtables, functions and variables, with the callbacks and type aliases beside them.
/// </summary>
public class ApiModel
{
    /// <summary>Every enum read, in the order the description lists them.</summary>
    public List<ApiEnum> Enums { get; } = [];

    /// <summary>Every struct and every vtable read, in the order the description lists them. A vtable's slots are on its <see cref="ApiStruct"/>.</summary>
    public List<ApiStruct> Structs { get; } = [];

    /// <summary>Every function read, in the order the description lists them.</summary>
    public List<ApiFunction> Functions { get; } = [];

    /// <summary>Every exported global read, in the order the description lists them.</summary>
    public List<ApiVariable> Variables { get; } = [];

    /// <summary>
    /// Function-pointer typedefs, keyed by the name a parameter is declared with.
    /// <see cref="TypeAliases"/> also holds each one, spelled as a type; this holds the
    /// description a projection needs to name the lanes.
    /// </summary>
    public List<ApiCallback> Callbacks { get; } = [];

    /// <summary>The callback a parameter's type names, or <see langword="null"/> if it names none.</summary>
    public ApiCallback? CallbackOf(string type) => Callbacks.FirstOrDefault(c => c.Name == type.Trim());

    /// <summary>
    /// Typedefs that resolve to a plain C primitive (<c>ke_entity</c> -&gt; <c>uint64_t</c>),
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

/// <summary>Reads the JSON description of one header into an <see cref="ApiModel"/>.</summary>
/// <remarks>
/// <see cref="Read"/> fills one model in a fixed order: the enums, then the structs, then the
/// vtables, which go through the same reader with their slots read as well, then the
/// <c>type_aliases</c>, the <c>callbacks</c>, the functions and the variables. The keys
/// <c>enums</c>, <c>structs</c>, <c>vtables</c> and <c>functions</c> are required, and a missing
/// one throws. The keys <c>callbacks</c>, <c>variables</c> and <c>type_aliases</c> are optional,
/// and an absent one leaves nothing to read. A value of the wrong JSON kind throws from the
/// conversion that asks for it. An enum and a struct read <c>external</c>, <c>tags</c> and
/// <c>doc</c> when present, and a slot also reads its <c>return_tags</c> and its <c>receiver</c>.
/// A parameter requires its <c>tags</c> key.
/// </remarks>
public static class ApiReader
{
    /// <summary>Reads the root object of a header description into a new model.</summary>
    /// <param name="root">The root object of the description, with the keys described in the type remarks.</param>
    /// <returns>The model holding every declaration the description lists.</returns>
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

        foreach (var c in root["callbacks"]?.AsArray() ?? [])
        {
            var o = c!.AsObject();
            m.Callbacks.Add(new ApiCallback(Str(o, "name")!, Str(o, "returns")!, Str(o, "doc"),
                o["lanes"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList()));
        }

        foreach (var f in root["functions"]!.AsArray())
        {
            var o = f!.AsObject();
            m.Functions.Add(new ApiFunction(Str(o, "name")!, Str(o, "returns")!, Str(o, "doc"), Str(o, "return_doc"),
                o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList())
            {
                ReturnTags = ReadTags(o, "return_tags"),
            });
        }
        foreach (var v in root["variables"]?.AsArray() ?? [])
        {
            var o = v!.AsObject();
            m.Variables.Add(new ApiVariable(Str(o, "name")!, Str(o, "type")!, Str(o, "doc")));
        }
        return m;
    }

    static ApiSlot ReadSlot(System.Text.Json.Nodes.JsonObject o) => new(Str(o, "name")!, Str(o, "returns")!,
        o["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [], Str(o, "doc"),
        Str(o, "return_doc"), o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList())
    {
        ReturnTags = ReadTags(o, "return_tags"),
        Receiver = Str(o, "receiver"),
    };

    static List<string> ReadTags(System.Text.Json.Nodes.JsonObject o, string key) =>
        o[key]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [];

    static ApiParam ReadParam(System.Text.Json.Nodes.JsonObject o) => new(Str(o, "name"), Str(o, "type")!,
        o["tags"]!.AsArray().Select(t => t!.GetValue<string>()).ToList(), Str(o, "doc"));

    static string? Str(System.Text.Json.Nodes.JsonObject o, string key) => o[key]?.GetValue<string>();
}
