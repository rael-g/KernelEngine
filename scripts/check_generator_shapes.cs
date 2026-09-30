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
        Slot("drop", "void", "unroots:entity", Param("entity", "ke_entity")),
        Slot("instance_of", "bool", "try", Param("entity", "ke_entity"),
             Param("out_type", "uint32_t *", "out"),
             Param("out_instance", "void **", "out,rooted"))),
    contains: ["public void Bind(ulong entity, object instance)", "GCHandle.Alloc(instance)",
               "_rooted[entity] = instanceHandle;", "freed.Free();",
               "public bool TryInstanceOf(ulong entity, out uint type, out object? instance)",
               "nint instanceLocal;",
               "instance = instanceLocal == 0 ? null :"
               + " System.Runtime.InteropServices.GCHandle.FromIntPtr(instanceLocal).Target;"],
    absent: ["public void Bind(ulong entity, nint instance)", "out nint instance)"]);

// The read side only means anything because the write side handed over a handle, so a
// pointer the native side would have to dereference cannot be one.
Expect("a rooted written-back parameter that is not an opaque pointer is refused",
    Vtable("ke_probe", Slot("instance_of", "bool", "try", Param("entity", "ke_entity"),
        Param("out_instance", "uint64_t *", "out,rooted"))),
    contains: [], absent: [],
    throws: "a rooted pointer is the one thing it never does");

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
    contains: ["public ulong Ask(ulong entity, out ProbeVerdict kind)", "ProbeVerdict kindLocal;",
               "(ke_probe_verdict*)&kindLocal", "kind = kindLocal;"],
    absent: ["ProbeVerdict* outKind", "public ProbeVerdict Ask("]);

// A slot answering with a declared enum. The same type as a parameter is already projected
// by name, so leaving the return as the ABI's integer would make one declaration mean two
// things depending on which side of the slot it sits on -- and hand every call site the cast
// back to the names the header already gave the values.
Expect("a slot answering with a declared enum answers in its names",
    Vtable("ke_probe", Slot("verdict_of", "ke_probe_verdict",
        Param("entity", "ke_entity"))),
    contains: ["public ProbeVerdict VerdictOf(ulong entity)",
               "return (ProbeVerdict)Handle->verdict_of(Handle, entity);"],
    absent: ["public ke_probe_verdict VerdictOf("]);

// The same stripping, where the name it would free is already taken. Picking a winner here
// would hand two of the slot's parameters to the caller under one name, and which one the
// caller then reads is not something the header says.
Expect("a stripped out_ name colliding with a declared parameter is refused",
    Vtable("ke_probe", Slot("ask_kind", "void",
        Param("kind", "uint32_t"),
        Param("out_kind", "uint32_t *", "out"))),
    contains: [], absent: [],
    throws: "already answers to kind");

// A slot answering with the front of a sequence and the count beside it: the two are one
// value, so the caller supplies neither pointer. Left apart, the count stays an out
// parameter and the return stays a raw pointer, which makes every call site re-derive the
// same bounds -- the arithmetic a projection exists to have already done once.
Expect("a returned pointer counted by an out parameter becomes a span",
    Vtable("ke_probe", Slot("samples", "const uint32_t *",
        Param("type", "uint32_t"),
        Param("out_count", "uint32_t *", "out"),
        Returning("array_of:out_count"))),
    contains: ["public ReadOnlySpan<uint> Samples(uint type)", "uint countLocal = 0;",
               "var front = Handle->samples(Handle, type, &countLocal);",
               "return front == null ? default : new ReadOnlySpan<uint>(front, (int)countLocal);"],
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
               "var front = Native.ke_probe_ctx_samples((ke_probe_ctx*)ctx, query, &countLocal);",
               "nuint countLocal = 0;",
               "return front == null ? default : new ReadOnlySpan<uint>(front, (int)countLocal);",
               "public static (uint Index, uint Count) Share(nint ctx)",
               "Native.ke_probe_ctx_share((ke_probe_ctx*)ctx, &index, &count);",
               "return (index, count);"],
    absent: ["in ke_probe_ctx ctx", "fixed (ke_probe_ctx* p =",
             "Samples(nint ctx, uint query, nuint* outCount)", "out uint index"]);

// An opaque payload bounded by a byte count. The caller already holds the value as a type,
// so the pair travels as that type and the count is derived from it -- left apart, the
// caller passes the address and the size of the same variable and nothing relates the two.
ExpectFreeFunctions("an opaque payload counted in bytes takes the caller's own type",
    [
        Function("ke_probe_ctx_attach", "bool",
            Param("ctx", "ke_probe_ctx *", "ctx"),
            Param("entity", "uint64_t"),
            Param("data", "const void *", "bytes_of:size"),
            Param("size", "size_t")),
    ],
    contains: ["public static bool Attach<TData>(nint ctx, ulong entity, in TData data)"
               + " where TData : unmanaged",
               "fixed (TData* dataPtr = &data)",
               "return Native.ke_probe_ctx_attach((ke_probe_ctx*)ctx, entity, (void*)dataPtr,"
               + " (nuint)sizeof(TData));"],
    absent: ["public static bool Attach(nint"]);

// The same tag on a pointer that already names its type. Deriving the count from a type
// parameter there would let the caller name a second type over bytes the declaration has
// already spoken for.
Expect("a typed pointer tagged as an opaque payload is refused",
    Vtable("ke_probe", Slot("write", "void",
        Param("data", "const uint32_t *", "bytes_of:size"),
        Param("size", "size_t"))),
    contains: [], absent: [],
    throws: "already names one");

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
// so. A value struct is not: a string is a reference of another size, so the field stays
// the bytes the ABI reads and the arity moves into the wrapper that occupies them.
ExpectValueStruct("a value struct's fixed char array stays the bytes it is",
    ValueStruct("ke_named", ("name", "char [64]")),
    contains: ["public const int NameCapacity = 64;", "public NameBuffer Name;",
               "[InlineArray(NameCapacity)]", "public partial struct NameBuffer",
               "public sbyte Element;"],
    absent: ["public string Name;"]);

// The matrix the ABI declares as a run of floats, taking the managed type of the same
// bytes. Left as the ABI struct, a caller composing a transform would be doing matrix
// arithmetic against a type that has none.
ExpectValueStruct("a value struct's matrix field takes the managed matrix type",
    ValueStruct("ke_world_transform", ("matrix", "ke_mat4")),
    contains: ["using System.Numerics;", "public Matrix4x4 Matrix;"],
    absent: ["ke_mat4"]);

// The neutral value of every field, seeded from the header that states it. Zero is a value
// the ABI reads as itself, so a default-constructed instance is not neutral -- and spelling
// the neutral surface a second time by hand is how the two come to disagree.
ExpectValueStruct("a value struct seeds the defaults the header states",
    TaggedValueStruct("ke_surface_component",
        ("base_color", "ke_vec4", ["default:1 1 1 1"]),
        ("roughness", "float", ["default:1"]),
        ("layers", "uint32_t", ["default:1"]),
        ("offset", "ke_vec2", [])),
    contains: ["public static SurfaceComponent Default => new()",
               "BaseColor = new Vector4(1f, 1f, 1f, 1f),", "Roughness = 1f,", "Layers = 1,"],
    absent: ["Offset ="]);

// A component's registered name is its only identity across languages, and the struct the
// ABI declares is where that name comes from. A caller spelling it as a literal beside the
// type is a second producer of the same identity, and renaming one compiles clean.
ExpectValueStruct("a component value struct carries the name it is registered under",
    ValueStruct("ke_point_light_component", ("intensity", "float")),
    contains: ["public const string Name = \"point_light\";"],
    absent: []);

// Plain value data is not a component and has no registered name to carry.
ExpectValueStruct("a value struct that is not a component carries no registered name",
    ValueStruct("ke_vertex_position", ("x", "float")),
    contains: [], absent: ["public const string Name"]);

// A default states one value; an array holds many. Seeding it from one would be a fill the
// header never described.
ExpectValueStruct("a value struct refuses a default on an array field",
    TaggedValueStruct("ke_named_default", ("name", "char [64]", ["default:none"])),
    contains: [], absent: [],
    throws: "states one value and the field holds an array");

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

// A node type's backing state is the component's own projection, so a property reads the
// field it names and nothing reinterprets bytes on the way. The alternative -- state typed
// as the raw binding struct -- needs a cast per property that checks size and not order, so
// it would keep passing after a field moved.
ExpectNodeType("a node type backs its state with the component's own projection",
    NodeStruct("ke_probe_component", "Probe3D",
        ("position", "ke_vec3", []),
        ("layers", "uint32_t", ["default:1"])),
    contains: ["[GeneratedNodeComponent(typeof(ProbeComponent), \"probe\")]",
               "public partial class Probe3D : Node",
               "_generatedState0 = ProbeComponent.Default;",
               "[NativeField(\"Position\", Component = typeof(ProbeComponent))]",
               "public partial Vector3 Position { get; set; }",
               "[NativeField(\"Layers\", Component = typeof(ProbeComponent))]"],
    absent: ["typeof(ke_probe_component)", "ke_vec3", "_generatedState0.position"]);

// A node whose header states no default seeds nothing: the projection's Default exists only
// where a field declares one, and a constructor naming it otherwise would not compile.
ExpectNodeType("a node type with no stated default seeds nothing",
    NodeStruct("ke_bare_component", "Bare", ("value", "float", [])),
    contains: ["public Bare()"],
    absent: ["Default;"]);

// The component struct a [node:] tag implies. The node's state has to be a projection with
// the same layout, so declaring the node is enough -- [value] beside it would be the same
// fact stated twice, and a node whose struct someone forgot to tag would back its state
// with the binding type instead.
ExpectValueStruct("a node component is projected without saying [value] as well",
    NodeStruct("ke_probe_component", "Probe3D", ("position", "ke_vec3", [])),
    contains: ["public partial struct ProbeComponent", "public const string Name = \"probe\";",
               "public Vector3 Position;"],
    absent: []);

// A struct the ABI hands out carrying a pointer and the count bounding it. The pair is one
// value wherever it sits: a slot answering with it already hands out a span, so a field
// answering with it that does not is the same declaration read two ways -- and every caller
// re-derives bounds the struct had already given.
ExpectStructSpans("a counted pointer field of a native struct reads as a span",
    CountedStruct("ke_probe_segment",
        ("entities", "const uint64_t *", "array_of:count"),
        ("count", "size_t", "")),
    contains: ["namespace Probe.Native;", "public unsafe partial struct ke_probe_segment",
               "public readonly ReadOnlySpan<ulong> Entities => entities == null ? default"
               + " : new ReadOnlySpan<ulong>(entities, (int)count);"],
    absent: ["public ulong* entities;", "MemoryMarshal", "Unsafe.As"]);

// The same tag naming a field the struct does not declare. Bounding the sequence by a
// length nothing holds is how a span reaches past what the ABI wrote.
ExpectStructSpans("a counted pointer field naming a length the struct lacks is refused",
    CountedStruct("ke_probe_segment",
        ("entities", "const uint64_t *", "array_of:total")),
    contains: [], absent: [],
    throws: "names a length field the struct does not declare");

// A struct nobody in managed code owns, read as a projection rather than mirrored as
// bytes. Every field is private: a pointer and its count are one sequence, and a fixed
// char array read as its bytes is text spelled as storage. The element is named after the
// projection of what the pointer reaches, not after the ABI spelling -- the two occupy the
// same bytes, so a reading that reinterpreted one as the other would assert a layout the
// compiler was never shown.
ExpectView("a view hands out its counted pointer, its text and its scalars, and keeps its fields private",
    ViewStruct("ke_probe_bundle",
        ("vertices", "ke_vertex *", "array_of:vertex_count"),
        ("vertex_count", "uint32_t", ""),
        ("material_index", "int32_t", ""),
        ("name", "char [64]", "")),
    contains: ["public unsafe partial struct ProbeBundle",
               "private readonly Vertex* vertices;",
               "private readonly uint vertex_count;",
               "private fixed sbyte name[64];",
               "public readonly ReadOnlySpan<Vertex> Vertices => vertices == null ? default"
               + " : new ReadOnlySpan<Vertex>(vertices, (int)vertex_count);",
               "public readonly int MaterialIndex => material_index;",
               "fixed (sbyte* p = name) return Marshal.PtrToStringUTF8((nint)p) ?? \"\";"],
    absent: ["public readonly uint VertexCount", "ReadOnlySpan<ke_vertex>", "ke_vertex*",
             "MemoryMarshal", "Unsafe.As"]);

// The same form with nothing bounding the pointer. A view exists to read memory it does
// not own, and a pointer with no extent is the one reading nobody can make safely -- so it
// is refused at the declaration rather than handed out as a bare pointer for a caller to
// guess the length of.
ExpectView("a view field reaching somewhere with no extent is refused",
    ViewStruct("ke_probe_bundle", ("pixels", "uint8_t *", "")),
    contains: [], absent: [],
    throws: "has to name the count bounding it");

// The same projection reached through a slot rather than a field. A view and the
// declaration it stands for occupy the same bytes, so the boundary names the projection on
// both sides -- handing one out and taking one back -- and the ABI spelling survives only
// as the cast the generated body makes. Without this the caller holds the C name and has to
// reinterpret it, which is the reading the form exists to stop being written by hand.
Expect("a slot hands out and takes back the projection of a [view], casting at the ABI",
    Vtable("ke_probe",
        Slot("open", "ke_probe_bundle *", Param("self", "ke_probe *", "self")),
        Slot("close", "void", Param("self", "ke_probe *", "self"),
            Param("bundle", "ke_probe_bundle *"))),
    contains: ["public ProbeBundle* Open(", "return (ProbeBundle*)Handle->open(",
               "ProbeBundle* bundle)", "(ke_probe_bundle*)bundle"],
    absent: ["ke_probe_bundle* Open", "ke_probe_bundle* bundle)"],
    structs: [ViewJson("ke_probe_bundle")]);

// The same pair of slots, once the release slot says it is the release slot. A [view] says
// how to read the memory and nothing about who frees it, and reading it as a value drops the
// pointer the release needs -- so a caller handed the bare pointer has to carry it beside
// the reading and remember to give it back. Naming the pairing is what turns that
// bookkeeping into one object with one answer about when the memory goes, and it is why the
// release stops being something a caller can reach at all.
Expect("[releases] pairs a handed-out pointer with the object that gives it back",
    Vtable("ke_probe",
        Slot("open", "ke_probe_bundle *", Param("self", "ke_probe *", "self"),
            Param("out_error", "ke_error **")),
        Slot("close", "void", "releases:Bundle", Param("self", "ke_probe *", "self"),
            Param("bundle", "ke_probe_bundle *"))),
    contains: ["public unsafe sealed class Bundle : IDisposable",
               "public ProbeBundle Data => _native is null",
               "_owner.Close(native);",
               "public Bundle Open(", "return new Bundle(this, result);",
               "internal void Close(ke_probe* self, ProbeBundle* bundle)"],
    absent: ["public void Close(", "ProbeBundle* Open("],
    structs: [ViewJson("ke_probe_bundle")]);

// A slot answering with owned memory and no way to say why it answered with nothing. The
// engine reports every failure through ke_error, so a bare null is a failure with the reason
// discarded -- and the caller of a generated projection has no second channel to consult.
Expect("owned memory handed out with no failure channel is refused",
    Vtable("ke_probe",
        Slot("open", "ke_probe_bundle *", Param("self", "ke_probe *", "self")),
        Slot("close", "void", "releases:Bundle", Param("self", "ke_probe *", "self"),
            Param("bundle", "ke_probe_bundle *"))),
    contains: [], absent: [],
    structs: [ViewJson("ke_probe_bundle")],
    throws: "has no failure channel");

// A slot that needs another domain's vtable to do its work. The pointer is what the ABI
// takes and the one thing a game-facing signature must not name -- and the caller already
// holds the projection carrying it, so asking for the projection and opening it at the call
// is the only spelling that does not make every caller reach inside first.
Expect("[provider] asks for another domain's projection, not the pointer inside it",
    Vtable("ke_probe",
        Slot("attach", "void", Param("self", "ke_probe *", "self"),
            Param("scheduler", "ke_scheduler *", "provider"),
            Param("out_error", "ke_error **"))),
    contains: ["Attach(ke_probe* self, INativeScheduler scheduler)", "scheduler.Native"],
    absent: ["ke_scheduler* scheduler", "ke_scheduler *scheduler"]);

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
    JsonObject[]? structs = null, string? throws = null)
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
/// Renders the node type a <c>[node:]</c> struct declares: the class a game writes against,
/// whose backing state and property surface come from the same struct the ABI declares.
/// </summary>
void ExpectNodeType(string what, ApiStruct component, string[] contains, string[] absent,
    ApiStruct[]? alongside = null)
{
    checks++;
    var model = new ApiModel();
    model.Structs.Add(component);
    foreach (var other in alongside ?? []) model.Structs.Add(other);

    var emitted = CSharpBackend.RenderNodeType(model, component, "Probe", [], Convention.KernelEngine);
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
        emitted = CSharpBackend.RenderStruct(model, s, "Probe", [], Convention.KernelEngine);
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

/// <summary>
/// A <c>[value]</c> struct whose fields carry tags of their own, which is what a default
/// stated in the header looks like by the time a backend reads it.
/// </summary>
static ApiStruct TaggedValueStruct(string name, params (string Name, string Type, string[] Tags)[] fields) =>
    new(name, null, ["value"],
        fields.Select(f => new ApiField(f.Name, f.Type, f.Tags, null)).ToList(), []);

/// <summary>
/// A component struct declaring the node type a game writes against, with per-field tags.
/// </summary>
static ApiStruct NodeStruct(string name, string node,
    params (string Name, string Type, string[] Tags)[] fields) =>
    new(name, null, [$"node:{node}"],
        fields.Select(f => new ApiField(f.Name, f.Type, f.Tags, null)).ToList(), []);

/// <summary>
/// A struct the ABI hands out, whose counted pointers are read as spans. The struct is the
/// ABI's own, not a <c>[value]</c> mirror, so this is the other emitter and so its own
/// fixture.
/// </summary>
void ExpectStructSpans(string what, ApiStruct s, string[] contains, string[] absent, string? throws = null)
{
    checks++;
    var model = new ApiModel();
    model.Structs.Add(s);

    string emitted;
    try
    {
        emitted = CSharpBackend.RenderStructSpans(model, s, "Probe.Native", Convention.KernelEngine);
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
/// A struct read as a projection of memory it does not own. The model carries the
/// <c>[value]</c> declaration the counted pointer reaches, because the element a view hands
/// out is that declaration's projection -- a fixture without it would check the one spelling
/// the form exists to stop emitting.
/// </summary>
void ExpectView(string what, ApiStruct s, string[] contains, string[] absent, string? throws = null)
{
    checks++;
    var model = new ApiModel();
    model.Structs.Add(s);
    model.Structs.Add(new ApiStruct("ke_vertex", null, ["value"],
        [new ApiField("x", "float", [], null)], []) { External = true });

    string emitted;
    try
    {
        emitted = CSharpBackend.RenderView(model, s, "Probe", ["Probe.Common"],
            Convention.KernelEngine);
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

static ApiStruct ViewStruct(string name, params (string Name, string Type, string Tags)[] fields) =>
    new(name, null, ["view"],
        fields.Select(f => new ApiField(f.Name, f.Type,
            f.Tags is "" ? [] : f.Tags.Split(','), null)).ToList(), []);

static ApiStruct CountedStruct(string name, params (string Name, string Type, string Tags)[] fields) =>
    new(name, null, [],
        fields.Select(f => new ApiField(f.Name, f.Type,
            f.Tags is "" ? [] : f.Tags.Split(','), null)).ToList(), []);

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

/// <summary>
/// A struct declared as the reading of memory it does not own, as the description carries
/// it. Only the tag matters to a slot boundary: what the projection hands out is the field
/// fixtures' question, while a slot only has to name the projection instead of the C type.
/// </summary>
static JsonObject ViewJson(string name) => new()
{
    ["name"] = name,
    ["doc"] = null,
    ["tags"] = new JsonArray((JsonNode)"view"),
    ["fields"] = new JsonArray(new JsonObject
        { ["name"] = "count", ["type"] = "uint32_t", ["tags"] = new JsonArray(), ["doc"] = null }),
    ["slots"] = new JsonArray(),
};

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
