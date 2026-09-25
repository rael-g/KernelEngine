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

// A run of consecutive float parameters that spell out one vector: the public surface
// takes the vector, and the lanes are spread at the call. A C ABI cannot say "Vector2",
// so without this every such slot grows a hand-written overload whose only content is
// which argument goes where.
Expect("consecutive lanes become one vector parameter",
    Vtable("ke_probe", Slot("set_gravity", "void",
        Param("x", "float", "vector2:gravity"),
        Param("y", "float"))),
    contains: ["public void SetGravity(Vector2 gravity)", "gravity.X, gravity.Y", "using System.Numerics;"],
    absent: ["SetGravity(float x, float y)"]);

// The lane run keeps its place among ordinary parameters rather than being hoisted.
Expect("a vector parameter does not disturb the parameters around it",
    Vtable("ke_probe", Slot("apply_impulse", "void",
        Param("body", "uint32_t"),
        Param("impulse_x", "float", "vector2:impulse"),
        Param("impulse_y", "float"),
        Param("wake", "ke_bool"))),
    contains: ["public void ApplyImpulse(uint body, Vector2 impulse, bool wake)",
               "body, impulse.X, impulse.Y, wake ? (byte)1 : (byte)0"],
    absent: ["float impulseX"]);

// A function pointer paired with an opaque context: the two are one closure, and the
// public surface takes one delegate. A managed handler can throw underneath native
// frames that cannot carry an exception, so the trampoline parks it and the call
// rethrows — swallowing it instead loses the failure entirely.
Expect("a callback and its context become one delegate parameter",
    Vtable("ke_probe", Slot("watch", "bool",
        Param("on_event", "ke_probe_event_func", "closure:event_ctx"),
        Param("event_ctx", "void *"),
        Param("out_error", "ke_error **"))),
    contains: ["public unsafe delegate void ProbeEvent(uint tick);",
               "public void Watch(ProbeEvent? onEvent)",
               "GCHandle.Alloc(onEvent)",
               "private static void WatchOnEventTrampoline(void* ctx, uint arg1)",
               "(delegate* unmanaged[Cdecl]<void*, uint, void>)&WatchOnEventTrampoline",
               "handler(arg1)",
               "s_parkedCallbackException ??= ex;",
               "throw parked;",
               "onEventHandle.Free();"],
    absent: ["void* eventCtx", "ke_probe_event_func onEvent", "_retainedOnEvent"],
    aliases: new() { ["ke_probe_event_func"] = "void (*)(void *, uint32_t)" },
    callbacks: [Callback("ke_probe_event_func", "void",
        Param("ctx", "void *", "context"), Param("tick", "uint32_t"))]);

// A closure the engine keeps after the call that registered it, one per key it is
// registered against. It is only projectable because the callback carries an error
// channel of its own: parking would have nothing to rethrow it once the registering
// call has already returned, which is how an asynchronous failure gets lost.
Expect("a retained closure is kept per key and reports through the channel it declares",
    Vtable("ke_probe", Slot("register_apply", "bool",
        Param("cid", "uint32_t"),
        Param("apply", "ke_probe_apply_fn", "closure:ctx,retained:cid"),
        Param("ctx", "void *"),
        Param("out_error", "ke_error **"))),
    contains: ["public unsafe delegate bool ProbeApply(uint tick);",
               "private readonly Dictionary<uint, GCHandle> _retainedApply = new();",
               "public void RegisterApply(uint cid, ProbeApply? apply)",
               "private static bool RegisterApplyTrampoline(void* ctx, uint arg1, ke_error** arg2)",
               "KernelError.ToNative(arg2, ex, \"ke_probe_apply_fn\");",
               "if (_retainedApply.Remove(cid, out var replacedApply)) replacedApply.Free();",
               "_retainedApply[cid] = applyHandle;",
               "foreach (var retained in _retainedApply.Values) retained.Free();"],
    absent: ["s_parkedCallbackException", "void* ctx)", "applyHandle.Free();\n        _retainedApply"],
    aliases: new() { ["ke_probe_apply_fn"] = "bool (*)(void *, uint32_t, ke_error **)" },
    callbacks: [Callback("ke_probe_apply_fn", "bool",
        Param("ctx", "void *", "context"), Param("tick", "uint32_t"),
        Param("out_error", "ke_error **"))]);

// A params bag the caller fills field by field, not a struct it has to assemble: the
// bag is rebuilt at the call site so the public surface stays one flat parameter list.
// Both hooks travel on the one context field, so they share the single object it points
// at — a handle each would hand every trampoline whichever one the call wrote last. The
// teardown hook has no error channel because the engine calls it from the destroy this
// object drives, which is the call that rethrows what it parked.
Expect("an expanded params bag flattens the call and its shared context roots one object",
    Vtable("ke_probe", Slot("register_module", "uint64_t",
        Param("p", "const ke_probe_module_params *", "expand"),
        Param("out_error", "ke_error **"))),
    contains: ["public ulong RegisterModule(string name, ProbeLoad? onLoad, ProbeUnload? onUnload)",
               "private readonly Dictionary<ulong, GCHandle> _retainedUserData = new();",
               "GCHandle.Alloc(new RegisterModuleClosures { OnLoad = onLoad, OnUnload = onUnload })",
               "ke_probe_module_params p = default;",
               "p.user_data = (void*)GCHandle.ToIntPtr(userDataHandle);",
               "result = Handle->register_module(Handle, &p, &err);",
               "if (userDataHandle.IsAllocated) _retainedUserData[result] = userDataHandle;",
               "return result;",
               "private sealed class RegisterModuleClosures",
               "state.OnLoad is { } handler",
               "state.OnUnload is { } handler",
               "s_parkedCallbackException ??= ex;",
               "s_parkedCallbackException = null;\n        _destroy(_native);",
               "foreach (var retained in _retainedUserData.Values) retained.Free();",
               "throw parked;"],
    absent: ["ke_probe_module_params* p", "void* userData", "onLoadHandle", "onUnloadHandle"],
    aliases: new() { ["ke_probe_load_fn"] = "bool (*)(void *, ke_error **)",
                     ["ke_probe_unload_fn"] = "void (*)(void *)" },
    callbacks: [Callback("ke_probe_load_fn", "bool",
                    Param("ctx", "void *", "context"), Param("out_error", "ke_error **")),
                Callback("ke_probe_unload_fn", "void",
                    Param("ctx", "void *", "context"))],
    structs: [new JsonObject
    {
        ["name"] = "ke_probe_module_params",
        ["doc"] = null,
        ["tags"] = new JsonArray(),
        ["fields"] = new JsonArray(
            Param("name", "const char *", "utf8"),
            Param("user_data", "void *", "context"),
            Param("on_load", "ke_probe_load_fn", "closure:user_data"),
            Param("on_unload", "ke_probe_unload_fn", "closure:user_data,retained:return,teardown")),
        ["slots"] = new JsonArray(),
    }]);

// A lane carrying a context the engine owns and the caller only relays: the public
// surface takes nint and the cast back to the ABI's own spelling happens at the call.
// Leaving the native pointer type in the signature is what forces every consumer to
// be compiled unsafe just to pass a value it never looks at.
Expect("a context lane is an nint the caller relays, not a native pointer",
    Vtable("ke_probe", Slot("spawn", "ke_entity",
        Param("sys", "ke_system_ctx *", "ctx"),
        Param("parent", "ke_entity"))),
    contains: ["public ulong Spawn(nint sys, ulong parent)", "(ke_system_ctx*)sys, parent"],
    absent: ["ke_system_ctx* sys"]);

// A slot that only answers, with nothing to ask and no way to fail: a property reads as
// what it is, state the provider already holds. Emitted as a method it grows a
// hand-written property beside it whose whole body is the call it wraps.
Expect("a slot that only answers becomes a property, in the class and in the contract alike",
    Vtable("ke_probe", "interface", Slot("root", "ke_entity", "property")),
    contains: ["public ulong Root", "get => Handle->root(Handle);",
               "public unsafe interface IProbe : IDisposable", "    ulong Root { get; }"],
    absent: ["public ulong Root()", "    ulong Root;"]);

// Data a caller holds, emitted from the header rather than spelled a second time by
// hand. The second spelling is what makes a reinterpret cast necessary, and a cast is
// only ever as true as the sentence written next to it.
ExpectValueStruct("a value struct is emitted with its layout pinned",
    ValueStruct("ke_vertex", ("x", "float"), ("y", "float"), ("z", "float")),
    contains: ["[StructLayout(LayoutKind.Sequential)]", "public partial struct Vertex",
               "public float X;", "public float Y;", "public float Z;"],
    absent: ["MemoryMarshal", "Unsafe.As"]);

// A pointer field would make the struct a view onto memory somebody else owns, which is
// a lifetime question a plain value cannot answer. Emitting it anyway is how a span with
// no owner reaches game code.
ExpectValueStruct("a value struct refuses a pointer field",
    ValueStruct("ke_mesh_data", ("vertices", "ke_vertex *")),
    contains: [], absent: [],
    throws: "makes the lifetime of that data someone else's question");

// The ABI's math primitives are named structs, not loose lanes, so they map by type
// rather than by a tag naming the run. The managed equivalents occupy the same bytes,
// which is what lets the struct be handed over as itself.
ExpectValueStruct("a value struct's math fields take the managed math types",
    ValueStruct("ke_transform", ("position", "ke_vec3"), ("rotation", "ke_quat"), ("scale", "ke_vec3")),
    contains: ["using System.Numerics;", "public Vector3 Position;", "public Quaternion Rotation;",
               "public Vector3 Scale;"],
    absent: ["ke_vec3", "ke_quat"]);

// A fixed char array reads far better as a string, and a node property is allowed to say
// so. A value struct is not: a string is a reference, the array is bytes inline, and the
// struct crosses as itself.
ExpectValueStruct("a value struct refuses a fixed char array",
    ValueStruct("ke_named", ("name", "char [64]")),
    contains: [], absent: [],
    throws: "has no managed type of the same size");

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

void Expect(string what, JsonObject vtable, string[] contains, string[] absent,
    Dictionary<string, string>? aliases = null, JsonObject[]? callbacks = null,
    JsonObject[]? structs = null)
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
        ["callbacks"] = new JsonArray((callbacks ?? []).Cast<JsonNode>().ToArray()),
        ["functions"] = new JsonArray(),
        ["type_aliases"] = new JsonObject { ["ke_entity"] = "uint64_t" },
    };
    foreach (var extra in structs ?? [])
        api["structs"]!.AsArray().Add(extra);
    foreach (var (alias, target) in aliases ?? [])
        api["type_aliases"]!.AsObject()[alias] = target;

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

void ExpectValueStruct(string what, ApiStruct s, string[] contains, string[] absent, string? throws = null)
{
    checks++;
    var model = new ApiModel();
    model.Structs.Add(s);

    string emitted;
    try
    {
        emitted = CSharpBackend.RenderStruct(model, s, "Probe", Convention.KernelEngine);
    }
    catch (Exception ex)
    {
        if (throws is null) failures.Add($"{what}: the backend threw {ex.GetType().Name}: {ex.Message}");
        else if (!ex.Message.Contains(throws, StringComparison.Ordinal))
            failures.Add($"{what}: refused for the wrong reason: {ex.Message}");
        return;
    }
    if (throws is not null)
    {
        failures.Add($"{what}: expected the backend to refuse, it emitted instead");
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

static ApiStruct ValueStruct(string name, params (string Name, string Type)[] fields) =>
    new(name, null, ["value"],
        fields.Select(f => new ApiField(f.Name, f.Type, [], null)).ToList(), []);

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

static JsonObject Vtable(string name, params object[] rest)
{
    var tags = new JsonArray();
    var slots = new JsonArray();
    foreach (var item in rest)
    {
        if (item is JsonObject s) slots.Add(s);
        else if (item is string t) foreach (var one in t.Split(',')) tags.Add((JsonNode)one.Trim());
    }
    return new()
    {
        ["name"] = name,
        ["doc"] = null,
        ["tags"] = tags,
        ["fields"] = new JsonArray(new JsonObject { ["name"] = "handle", ["type"] = "void *", ["tags"] = new JsonArray(), ["doc"] = null }),
        ["slots"] = slots,
    };
}

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

static JsonObject Callback(string name, string returns, params JsonObject[] lanes) => new()
{
    ["name"] = name,
    ["returns"] = returns,
    ["doc"] = null,
    ["lanes"] = new JsonArray(lanes.Cast<JsonNode>().ToArray()),
};

static JsonObject Param(string name, string type, string tags = "") => new()
{
    ["name"] = name,
    ["type"] = type,
    ["tags"] = new JsonArray(tags.Length == 0 ? [] : tags.Split(',').Select(t => (JsonNode)t.Trim()).ToArray()),
    ["doc"] = null,
};
