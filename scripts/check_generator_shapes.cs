#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.CSharpBackend/Kabic.CSharpBackend.csproj

// Feeds the backend a header shape and checks what it emits.
//
// Run it with `dotnet run --no-cache`: the file-based runner will otherwise reuse a
// previously built kabic, so a change to the classifier is checked against the
// classifier as it was. That is not a detail — it made this very check pass while the
// defect it was written for was back in the tree.
//
// The other checks ask whether the committed output matches the headers, or whether a
// clean rebuild reproduces it. Both pass on output that is wrong in the same way it
// has always been wrong. This one states, per shape, what the C# is supposed to look
// like — so a change in how a slot is classified fails here rather than in whatever
// game first notices its return value went missing.

using System.Text.Json.Nodes;
using Kabic;
using Kabic.CSharp;

var failures = new List<string>();
var checks = 0;

// A slot that answers and also writes an out parameter: the answer is the return, and
// the out parameter stays a parameter. Getting this backwards compiles and silently
// drops what the caller asked for.
Expect("a slot with a return and an out parameter keeps both",
    Vtable("ke_probe", Slot("resolve", "ke_entity",
        Param("entity", "ke_entity"),
        Param("out_why", "ke_probe_verdict *", "out"))),
    contains: ["public ulong Resolve(ulong entity,"],
    absent: ["public ProbeVerdict Resolve("]);

// A slot with nothing to answer: the out parameter is the answer.
Expect("a void slot's single out parameter becomes the return",
    Vtable("ke_probe", Slot("size_of", "void",
        Param("out_size", "uint32_t *", "out"))),
    contains: ["public uint SizeOf("],
    absent: ["uint* outSize"]);

// A string parameter arrives as a string and is encoded at the boundary, not by the
// caller.
Expect("a utf8 parameter is a string on the public surface",
    Vtable("ke_probe", Slot("named", "ke_entity", Param("name", "const char *", "utf8"))),
    contains: ["public ulong Named(string name)", "Encoding.UTF8.GetBytes"],
    absent: ["sbyte* name)"]);

// An opaque pointer carrying a managed object: the backend roots it and frees it,
// rather than every binding runtime writing the same handle table.
Expect("a rooted parameter takes an object and is kept alive",
    Vtable("ke_probe",
        Slot("bind", "bool", Param("entity", "ke_entity"),
             Param("instance", "void *", "rooted:entity"),
             Param("out_error", "ke_error **")),
        Slot("drop", "void", "unroots:entity", Param("entity", "ke_entity"))),
    contains: ["public void Bind(ulong entity, object instance)", "GCHandle.Alloc(instance)",
               "_rooted[entity] = instanceHandle;", "freed.Free();"],
    absent: ["public void Bind(ulong entity, nint instance)"]);

// A slot that interns a type under a name and a size: the type-to-id cache is emitted
// once here instead of by hand in every consumer.
Expect("an interning slot emits the type cache and its reverse",
    Vtable("ke_probe", Slot("signal_id", "bool",
        Param("name", "const char *", "utf8,type_name"),
        Param("payload_size", "uint32_t", "type_size"),
        Param("out_id", "uint32_t *", "out"),
        Param("out_error", "ke_error **"), "interns")),
    contains: ["public uint SignalIdOf<T>() where T : unmanaged", "public Type? SignalIdTypeOf(uint id)"],
    absent: []);

// An enum parameter that is a pointer stays a pointer; taking it by value compiles
// into a cast from a value to a pointer, which does not.
Expect("an enum out parameter keeps its indirection",
    Vtable("ke_probe", Slot("ask", "ke_entity",
        Param("out_kind", "ke_probe_verdict *", "out,enum:ke_probe_verdict"))),
    contains: ["ProbeVerdict* outKind"],
    absent: ["ProbeVerdict outKind"]);

// An enum that names where a borrow looks: one wrapper per value, each carrying the
// reach it resolves with. What stops a projection from keeping its own list of borrow
// type names, which is a copy of this enum that nothing makes it update.
ExpectBorrowKinds("a borrow-kinds enum emits one wrapper per value, each marked with its reach",
    contains: [
        "public sealed class NodeBorrowAttribute : Attribute",
        "[NodeBorrow(ProbeReachKind.Near)]",
        "public readonly ref struct Near<T> where T : class",
        "public Near(T? node) => _node = node;",
        "[NodeBorrow(ProbeReachKind.Far)]",
        "public readonly ref struct Far<T> where T : class",
    ],
    absent: ["internal Near("]);

foreach (var f in failures) Console.Error.WriteLine($"  {f}");
if (failures.Count > 0)
{
    Console.Error.WriteLine($"\n{failures.Count} shape(s) are not emitted as declared.");
    return 1;
}
Console.WriteLine($"The backend emits all {checks} declared shape(s).");
return 0;

void Expect(string what, JsonObject vtable, string[] contains, string[] absent)
{
    checks++;
    var api = new JsonObject
    {
        ["enums"] = new JsonArray(new JsonObject
        {
            ["name"] = "ke_probe_verdict",
            ["doc"] = null,
            ["values"] = new JsonArray(new JsonObject
                { ["name"] = "KE_PROBE_VERDICT_NONE", ["rawValue"] = "0", ["isInt"] = true, ["doc"] = null }),
        }),
        // A vtable is only a provider once something can make one, so the fixture
        // carries the owner wrapper the convention looks for.
        ["structs"] = new JsonArray(new JsonObject
        {
            ["name"] = "ke_probe_handle",
            ["doc"] = null,
            ["tags"] = new JsonArray(),
            ["fields"] = new JsonArray(
                new JsonObject { ["name"] = "ref", ["type"] = "ke_probe *", ["tags"] = new JsonArray(), ["doc"] = null },
                new JsonObject { ["name"] = "destroy", ["type"] = "void (*)(ke_probe *)", ["tags"] = new JsonArray(), ["doc"] = null }),
            ["slots"] = new JsonArray(),
        }),
        ["vtables"] = new JsonArray(vtable),
        ["functions"] = new JsonArray(),
        ["type_aliases"] = new JsonObject { ["ke_entity"] = "uint64_t" },
    };

    string emitted;
    try
    {
        var model = ApiReader.Read(api);
        var convention = Convention.KernelEngine;
        var classified = Classifier.Classify(model, [], [], convention);
        var provider = classified.Providers.Single();
        emitted = CSharpBackend.RenderProvider(model, provider, classified, "Probe", "Probe.Native", [], convention);
    }
    catch (Exception ex)
    {
        failures.Add($"{what}: the backend threw {ex.GetType().Name}: {ex.Message}");
        return;
    }
    if (Environment.GetEnvironmentVariable("KE_SHAPES_DUMP") == what) Console.WriteLine(emitted);


    foreach (var needle in contains)
        if (!emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected to find \"{needle}\"");

    foreach (var needle in absent)
        if (emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected NOT to find \"{needle}\"");
}

void ExpectBorrowKinds(string what, string[] contains, string[] absent)
{
    checks++;
    var kinds = new ApiEnum("ke_probe_reach_kind", "Where a borrow looks.",
    [
        new ApiEnumValue("KE_PROBE_REACH_KIND_NEAR", "0", true, "Close by."),
        new ApiEnumValue("KE_PROBE_REACH_KIND_FAR", "1", true, "Further off."),
    ])
    { Tags = ["borrow_kinds"] };

    string emitted;
    try
    {
        emitted = CSharpBackend.RenderBorrowWrappers(kinds, "Probe", Convention.KernelEngine);
    }
    catch (Exception ex)
    {
        failures.Add($"{what}: the backend threw {ex.GetType().Name}: {ex.Message}");
        return;
    }
    if (Environment.GetEnvironmentVariable("KE_SHAPES_DUMP") == what) Console.WriteLine(emitted);

    foreach (var needle in contains)
        if (!emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected to find \"{needle}\"");

    foreach (var needle in absent)
        if (emitted.Contains(needle, StringComparison.Ordinal))
            failures.Add($"{what}: expected NOT to find \"{needle}\"");
}

static JsonObject Vtable(string name, params JsonObject[] slots) => new()
{
    ["name"] = name,
    ["doc"] = null,
    ["tags"] = new JsonArray(),
    ["fields"] = new JsonArray(new JsonObject { ["name"] = "handle", ["type"] = "void *", ["tags"] = new JsonArray(), ["doc"] = null }),
    ["slots"] = new JsonArray(slots.Cast<JsonNode>().ToArray()),
};

static JsonObject Slot(string name, string returns, params object[] rest)
{
    var tags = new JsonArray();
    var ps = new JsonArray();
    foreach (var item in rest)
    {
        if (item is JsonObject p) ps.Add(p);
        else if (item is string t) foreach (var one in t.Split(',')) tags.Add((JsonNode)one.Trim());
    }
    return new JsonObject
    {
        ["name"] = name,
        ["returns"] = returns,
        ["tags"] = tags,
        ["doc"] = null,
        ["returnDoc"] = null,
        ["params"] = ps,
    };
}

static JsonObject Param(string name, string type, string tags = "") => new()
{
    ["name"] = name,
    ["type"] = type,
    ["tags"] = new JsonArray(tags.Length == 0 ? [] : tags.Split(',').Select(t => (JsonNode)t.Trim()).ToArray()),
    ["doc"] = null,
};
