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

// A slot that answers and also writes: the answer stays the return and the written value
// becomes an out parameter. Hoisting it instead would silently drop what the caller asked
// for; leaving it the pointer the ABI takes makes every call site declare the local and
// take its address, which is the binding work a projection exists to have already done.
Expect("a slot that answers and writes spells the written value out",
    Vtable("ke_probe", Slot("ask", "ke_entity",
        Param("entity", "ke_entity"),
        Param("out_kind", "ke_probe_verdict *", "out,enum:ke_probe_verdict"))),
    contains: ["public ulong Ask(ulong entity, out ProbeVerdict outKind)", "ProbeVerdict outKindLocal;",
               "(ke_probe_verdict*)&outKindLocal", "outKind = outKindLocal;"],
    absent: ["ProbeVerdict* outKind", "public ProbeVerdict Ask("]);

// A slot answering with the front of a sequence and the count beside it: the two are one
// value, so the caller supplies neither pointer. Left apart, the count stays an out
// parameter and the return stays a raw pointer, which makes every call site re-derive the
// same bounds -- the arithmetic a projection exists to have already done once.
Expect("a returned pointer counted by an out parameter becomes a span",
    Vtable("ke_probe", Slot("samples", "const uint32_t *",
        Param("type", "uint32_t"),
        Param("out_count", "uint32_t *", "out"),
        Returning("array_of:out_count"))),
    contains: ["public ReadOnlySpan<uint> Samples(uint type)", "uint outCountLocal = 0;",
               "var front = Handle->samples(Handle, type, &outCountLocal);",
               "return front == null ? default : new ReadOnlySpan<uint>(front, (int)outCountLocal);"],
    absent: ["out uint outCount", "public uint* Samples("]);

// The same tags on a free function, which reaches a contract by symbol instead of by
// vtable field. A receiver declared [ctx] is the opaque token its callers already hold, so
// it is passed along rather than pinned as a value; what the function writes and what it
// returns are read exactly as a slot's are. Read differently, one header line would
// project two ways depending on which emitter got to it.
ExpectFreeFunctions("a free function honours [ctx], [out] and a counted return",
    [
        Function("ke_probe_ctx_samples", "const uint32_t *",
            Param("ctx", "ke_probe_ctx *", "ctx"),
            Param("query", "uint32_t"),
            Param("out_count", "size_t *", "out"),
            Returning("array_of:out_count")),
        Function("ke_probe_ctx_share", "void",
            Param("ctx", "ke_probe_ctx *", "ctx"),
            Param("out_index", "uint32_t *", "out"),
            Param("out_count", "uint32_t *", "out")),
    ],
    contains: ["public static ReadOnlySpan<uint> Samples(nint ctx, uint query)",
               "var front = Native.ke_probe_ctx_samples((ke_probe_ctx*)ctx, query, &outCountLocal);",
               "nuint outCountLocal = 0;",
               "return front == null ? default : new ReadOnlySpan<uint>(front, (int)outCountLocal);",
               "public static (uint OutIndex, uint OutCount) Share(nint ctx)",
               "Native.ke_probe_ctx_share((ke_probe_ctx*)ctx, &outIndex, &outCount);",
               "return (outIndex, outCount);"],
    absent: ["in ke_probe_ctx ctx", "fixed (ke_probe_ctx* p =",
             "Samples(nint ctx, uint query, nuint* outCount)", "out uint outIndex"]);

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
    contains: ["public delegate void ProbeEvent(uint tick);",
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
    contains: ["public delegate void ProbeApply(uint tick);",
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
// object drives, which is the call that rethrows what it parked. The bag says that hook
// may be left out, so the projection spells the absence instead of an overload whose only
// content is passing null.
Expect("an expanded params bag flattens the call and its shared context roots one object",
    Vtable("ke_probe", Slot("register_module", "uint64_t",
        Param("p", "const ke_probe_module_params *", "expand"),
        Param("out_error", "ke_error **"))),
    contains: ["public ulong RegisterModule(string name, ProbeLoad? onLoad, ProbeUnload? onUnload = null)",
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
            Param("on_unload", "ke_probe_unload_fn", "closure:user_data,retained:return,teardown,default:none")),
        ["slots"] = new JsonArray(),
    }]);

// A retained handler reporting through a lane of its own: the registering call has
// already returned by the time it fails, so there is nothing left to rethrow at. The
// exception is queued on the provider and raised by the slot that observes the failure,
// which is why the context has to point at an object naming that provider rather than at
// the delegate. Filling the lane and dropping the exception loses the type, the message
// and the stack of whatever actually went wrong.
Expect("a retained handler's exception is queued on its provider and raised where the failure is observed",
    Vtable("ke_probe",
        Slot("register_apply", "bool",
            Param("cid", "uint32_t"),
            Param("apply", "ke_probe_apply_fn", "closure:ctx,retained:cid"),
            Param("ctx", "void *"),
            Param("out_error", "ke_error **")),
        Slot("run", "bool", "drains", Param("out_error", "ke_error **"))),
    contains: ["private readonly System.Collections.Concurrent.ConcurrentQueue<Exception> _callbackFailures = new();",
               "private void DrainCallbackFailures()",
               "GCHandle.Alloc(new RegisterApplyClosures { Owner = this, Apply = apply })",
               "public required Probe Owner;",
               "failed.Owner._callbackFailures.Enqueue(ex);",
               "if (!Handle->run(Handle, &err) && _callbackFailures.IsEmpty)",
               "DrainCallbackFailures();"],
    absent: ["GCHandle.Alloc(apply)"],
    aliases: new() { ["ke_probe_apply_fn"] = "bool (*)(void *, uint32_t, ke_error **)" },
    callbacks: [Callback("ke_probe_apply_fn", "bool",
        Param("ctx", "void *", "context"), Param("tick", "uint32_t"),
        Param("out_error", "ke_error **"))]);

// A pointer+count pair is a property of the parameter, not of the slot: a slot may
// carry several, and each one still pins and passes its own length. Treating "carries a
// sequence" as the slot's shape is what caps a slot at one array and blocks it from
// composing with the rest.
Expect("every pointer+count pair in a slot becomes its own span",
    Vtable("ke_probe", Slot("declare", "uint64_t",
        Param("name", "const char *", "utf8"),
        Param("terms", "const ke_probe_term *", "array_of:term_count"),
        Param("term_count", "uint32_t"),
        Param("tags", "const uint32_t *", "array_of:tag_count"),
        Param("tag_count", "uint32_t"),
        Param("out_error", "ke_error **"))),
    contains: ["public ulong Declare(string name, Span<ke_probe_term> terms, Span<uint> tags)",
               "fixed (ke_probe_term* termsPtr = terms)",
               "fixed (uint* tagsPtr = tags)",
               "termsPtr, (uint)terms.Length, tagsPtr, (uint)tags.Length"],
    absent: ["uint termCount", "uint tagCount"],
    structs: [new JsonObject
    {
        ["name"] = "ke_probe_term",
        ["doc"] = null,
        ["tags"] = new JsonArray(),
        ["fields"] = new JsonArray(Param("cid", "uint32_t")),
        ["slots"] = new JsonArray(),
    }]);

// A slot says for itself that its projection is the unadorned one something above is
// expected to wrap. Inferring it from "carries a sequence" names three slots Raw that
// nothing wraps, and puts the suffix on a contract game code reads.
Expect("only a slot declaring itself raw takes the suffix",
    Vtable("ke_probe", Slot("drain", "uint32_t", "raw",
        Param("out_buf", "uint32_t *", "out,array_of:capacity"),
        Param("capacity", "uint32_t"))),
    contains: ["public uint DrainRaw(Span<uint> outBuf)"],
    absent: ["public uint Drain("]);

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

// The same relay rule, one level down: a lane of a callback the caller implements. A
// handler is game-facing code, so leaving the ABI's pointer in the delegate would make
// every body that never looks at it compile unsafe.
//
// A handler reporting through an error channel says failure by throwing, so the boolean
// it returns natively is not the caller's to answer: the delegate returns nothing and
// the trampoline reports for it.
Expect("a handler relays a context lane as nint and reports its own failure by throwing",
    Vtable("ke_probe", Slot("register_body", "bool",
        Param("body", "ke_probe_body_fn", "closure:ctx"),
        Param("ctx", "void *"),
        Param("out_error", "ke_error **"))),
    contains: ["public delegate void ProbeBody(nint sys, float dt);",
               "handler((nint)arg0, arg2);",
               "return true;"],
    absent: ["delegate bool ProbeBody", "ke_system_ctx* sys"],
    aliases: new() { ["ke_probe_body_fn"] = "bool (*)(ke_system_ctx *, void *, float, ke_error **)" },
    callbacks: [Callback("ke_probe_body_fn", "bool",
        Param("sys", "ke_system_ctx *", "ctx"), Param("ctx", "void *", "context"),
        Param("dt", "float"), Param("out_error", "ke_error **"))]);

// A lane typed as the provider the call was made on: managed code already holds the
// wrapper for that pointer, so the handler is handed the wrapper. Reaching it means the
// context points at an object naming the provider — which is not the same reason the
// failure queue needs one, and a handler that runs inside the registering call still has
// its exception rethrown there rather than stored.
Expect("a handler called with the provider is handed the managed wrapper, not the pointer",
    Vtable("ke_probe", Slot("register_body", "bool",
        Param("body", "ke_probe_body_fn", "closure:ctx"),
        Param("ctx", "void *"),
        Param("out_error", "ke_error **"))),
    contains: ["public delegate void ProbeBody(Probe probe);",
               "public required Probe Owner;",
               "handler(state.Owner);"],
    absent: ["_callbackFailures", "ke_probe* probe"],
    aliases: new() { ["ke_probe_body_fn"] = "bool (*)(ke_probe *, void *, ke_error **)" },
    callbacks: [Callback("ke_probe_body_fn", "bool",
        Param("probe", "ke_probe *", "self"), Param("ctx", "void *", "context"),
        Param("out_error", "ke_error **"))]);

// A slot that only answers, with nothing to ask and no way to fail: a property reads as
// what it is, state the provider already holds. Emitted as a method it grows a
// hand-written property beside it whose whole body is the call it wraps.
Expect("a slot that only answers becomes a property, in the class and in the contract alike",
    Vtable("ke_probe", "interface", Slot("root", "ke_entity", "property")),
    contains: ["public ulong Root", "get => Handle->root(Handle);",
               "public interface IProbe : IDisposable", "    ulong Root { get; }"],
    absent: ["public ulong Root()", "    ulong Root;", "public unsafe interface IProbe"]);

// The keyword is a permission the project holding the file has to grant, and it grants it
// project-wide. A contract or a delegate naming nothing but managed types asks for pointers
// to be allowed everywhere around it, for the sake of a signature that spells none. So it
// follows the signature instead: absent above, present here.
Expect("a contract spelling a pointer keeps the keyword",
    Vtable("ke_probe", "interface", Slot("samples", "const uint32_t *")),
    contains: ["public unsafe interface IProbe : IDisposable", "    uint* Samples();"],
    absent: ["public interface IProbe : IDisposable"]);

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

// A fixed array of another value struct. C# cannot spell `T[8]` inline for a struct T, so
// the arity has to move into an [InlineArray] wrapper occupying the same bytes -- emitting
// the field as one element instead is how a caller writes past what the ABI reads.
ExpectValueStruct("a value struct's fixed array of value structs takes an inline-array buffer",
    ValueStruct("ke_query_decl", ("terms", "ke_component_access[8]"), ("term_count", "uint32_t")),
    contains: ["using System.Runtime.CompilerServices;", "public const int TermsCapacity = 8;",
               "public TermsBuffer Terms;", "public uint TermCount;", "[InlineArray(TermsCapacity)]",
               "public partial struct TermsBuffer", "public ComponentAccess Element;"],
    absent: ["public ke_component_access", "public ComponentAccess Terms;"],
    alongside: [ValueStruct("ke_component_access", ("cid", "uint32_t"), ("access", "uint32_t"))]);

// The element of a value struct's array is the other struct's own projection, not the
// native spelling of the same bytes -- otherwise one generated type's fields are another
// generator's, and the two drift independently.
ExpectValueStruct("a value struct naming another value struct takes its mirror",
    ValueStruct("ke_query_term", ("access", "ke_component_access")),
    contains: ["public ComponentAccess Access;"],
    absent: ["ke_component_access"],
    alongside: [ValueStruct("ke_component_access", ("cid", "uint32_t"), ("access", "uint32_t"))]);

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
        var source = CSharpBackend.RenderProvider(model, provider, classified, "Probe", "Probe.Native", [], convention);
        emitted = source.Class + (source.Contract ?? "");
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

void ExpectValueStruct(string what, ApiStruct s, string[] contains, string[] absent, string? throws = null,
    ApiStruct[]? alongside = null)
{
    checks++;
    var model = new ApiModel();
    model.Structs.Add(s);
    foreach (var other in alongside ?? []) model.Structs.Add(other);

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

/// <summary>
/// Renders the free functions of a bare struct: an operation reached by a symbol rather
/// than by a vtable field, which is a separate emitter and so a separate fixture.
/// </summary>
void ExpectFreeFunctions(string what, JsonObject[] functions, string[] contains, string[] absent)
{
    checks++;
    var api = new JsonObject
    {
        ["enums"] = new JsonArray(),
        ["structs"] = new JsonArray(new JsonObject
        {
            ["name"] = "ke_probe_ctx",
            ["doc"] = null,
            ["tags"] = new JsonArray(),
            ["fields"] = new JsonArray(
                new JsonObject { ["name"] = "handle", ["type"] = "void *", ["tags"] = new JsonArray(), ["doc"] = null }),
            ["slots"] = new JsonArray(),
        }),
        ["vtables"] = new JsonArray(),
        ["callbacks"] = new JsonArray(),
        ["functions"] = new JsonArray(functions.Cast<JsonNode>().ToArray()),
        ["type_aliases"] = new JsonObject(),
    };

    string emitted;
    try
    {
        var model = ApiReader.Read(api);
        var convention = Convention.KernelEngine;
        var classified = Classifier.Classify(model, [], [], convention);
        var (owner, group) = classified.FreeFunctionGroups.Single();
        emitted = CSharpBackend.RenderFreeFunctions(model, owner, group, "Probe", "Probe.Native",
            [], "ke_probe", convention);
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

static JsonObject Function(string name, string returns, params object[] rest)
{
    var returnTags = new JsonArray();
    var ps = new JsonArray();
    foreach (var item in rest)
    {
        if (item is JsonObject p) ps.Add(p);
        else if (item is ReturnTags rt) foreach (var one in rt.Tags.Split(',')) returnTags.Add((JsonNode)one.Trim());
    }
    return new JsonObject
    {
        ["name"] = name,
        ["returns"] = returns,
        ["doc"] = null,
        ["return_doc"] = null,
        ["return_tags"] = returnTags,
        ["params"] = ps,
    };
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
    var returnTags = new JsonArray();
    var ps = new JsonArray();
    foreach (var item in rest)
    {
        if (item is JsonObject p) ps.Add(p);
        else if (item is ReturnTags rt) foreach (var one in rt.Tags.Split(',')) returnTags.Add((JsonNode)one.Trim());
        else if (item is string t) foreach (var one in t.Split(',')) tags.Add((JsonNode)one.Trim());
    }
    return new JsonObject
    {
        ["name"] = name,
        ["returns"] = returns,
        ["tags"] = tags,
        ["doc"] = null,
        ["returnDoc"] = null,
        ["return_tags"] = returnTags,
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

/// <summary>Declares tags on a slot's return, for a fixture to pass among its parameters.</summary>
static ReturnTags Returning(string tags) => new(tags);

static JsonObject Param(string name, string type, string tags = "") => new()
{
    ["name"] = name,
    ["type"] = type,
    ["tags"] = new JsonArray(tags.Length == 0 ? [] : tags.Split(',').Select(t => (JsonNode)t.Trim()).ToArray()),
    ["doc"] = null,
};

/// <summary>What the slot's <c>@return</c> block declares, which is not the slot's own tag.</summary>
record ReturnTags(string Tags);
