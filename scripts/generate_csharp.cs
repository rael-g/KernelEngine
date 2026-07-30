#!/usr/bin/env dotnet run

// kabic's Classifier + CSharpBackend: generates an idiomatic C# layer from a
// ke_api.json description (produced by kabic's frontend, scripts/extract_api.cs).
// See docs/ScriptingArchitectureV3.md §6: this file deliberately keeps two
// passes separate —
//
//   §6.1 classification (language-independent): decide what a slot MEANS —
//     fallible, owned, a sequence, an enum, a callback — from the description
//     alone. `Classify()` below is that pass; nothing in it mentions C#.
//
//   §6.2 backend (C#-specific): decide how to SAY it — throw, IDisposable,
//     Span<T>, GCHandle + [UnmanagedCallersOnly]. `CSharpBackend` below is
//     that pass. A Lua/Python/Zig backend would consume the same
//     classification and differ only past this line.
//
// Output is generated code: never hand-edit it, regenerate from ke_api.json,
// same rule that already governs src/csharp/*/Native/Generated/.
//
// Usage: dotnet run scripts/generate_csharp.cs -- --api <ke_api.json>
//        --namespace <NS> --native-namespace <NS.Native> --out <dir>
//        [--provider <vtable_name>]... [--callback <vtable_name>]...
//
// A vtable not explicitly classified via --provider/--callback is inferred:
// referenced as a [callback]-tagged parameter type anywhere => callback;
// otherwise, if it has a matching ke_X_create factory function => provider.

using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

string? apiPath = null, ns = null, nativeNs = null, outDir = null, enumsOutDir = null, library = null;
var explicitProviders = new HashSet<string>();
var explicitCallbacks = new HashSet<string>();
var extraUsings = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--api": apiPath = args[++i]; break;
        case "--namespace": ns = args[++i]; break;
        case "--native-namespace": nativeNs = args[++i]; break;
        case "--out": outDir = args[++i]; break;
        case "--enums-out": enumsOutDir = args[++i]; break;
        case "--provider": explicitProviders.Add(args[++i]); break;
        case "--callback": explicitCallbacks.Add(args[++i]); break;
        // Mirrors generate_bindings.cs's .rsp `--with-using`: a factory param
        // that is a pointer into ANOTHER domain (e.g. ke_input_create's
        // `ke_logger*`) needs that domain's Native namespace in scope; nothing
        // in one domain's ke_api.json can name it, so the caller supplies it.
        case "--using": extraUsings.Add(args[++i]); break;
        // The native .so a value-type's free functions DllImport against. Not
        // derivable from ke_api.json (no plugin-to-.so mapping in the
        // description); required whenever a domain has free-function groups —
        // guessing it from the domain name is how ke_logger_simple almost
        // shipped as a DllImport against "ke_logger_default", which doesn't exist.
        case "--library": library = args[++i]; break;
    }
}

if (apiPath is null || ns is null || nativeNs is null || outDir is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_csharp.cs -- --api <ke_api.json> "
        + "--namespace <NS> --native-namespace <NS.Native> --out <dir> "
        + "[--provider <vtable>]... [--callback <vtable>]... [--using <NS>]... [--library <so-name>]");
    return 1;
}

var api = JsonNode.Parse(File.ReadAllText(apiPath))!.AsObject();
var model = ApiReader.Read(api);
var classified = Classifier.Classify(model, explicitProviders, explicitCallbacks);

Directory.CreateDirectory(outDir);

if (model.Enums.Count > 0)
{
    var enumsDir = enumsOutDir ?? outDir;
    Directory.CreateDirectory(enumsDir);
    File.WriteAllText(Path.Combine(enumsDir, "Enums.g.cs"), CSharpBackend.RenderEnums(model, ns));
}

foreach (var provider in classified.Providers)
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.StripPrefix(provider.Name)}.g.cs"),
        CSharpBackend.RenderProvider(model, provider, classified, ns, nativeNs, extraUsings));

foreach (var callback in classified.Callbacks)
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.StripPrefix(callback.Name)}Native.g.cs"),
        CSharpBackend.RenderCallbackInterface(callback, ns, nativeNs));

if (classified.FreeFunctionGroups.Count > 0)
    foreach (var (owner, fns) in classified.FreeFunctionGroups)
    {
        if (library is null)
        {
            Console.Error.WriteLine($"error: domain has free functions on '{owner}' but --library was not given");
            return 1;
        }
        File.WriteAllText(Path.Combine(outDir, $"{Idioms.StripPrefix(owner)}Functions.g.cs"),
            CSharpBackend.RenderFreeFunctions(owner, fns, ns, nativeNs, library));
    }

Console.WriteLine($"wrote {classified.Providers.Count} provider(s), {classified.Callbacks.Count} callback(s), "
    + $"{classified.FreeFunctionGroups.Count} free-function group(s) to {outDir}");
return 0;

// =============================================================================
// -- reading ke_api.json into a typed model ----------------------------------
// =============================================================================

record ApiParam(string? Name, string Type, IReadOnlyList<string> Tags, string? Doc)
{
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

record ApiSlot(string Name, string Returns, IReadOnlyList<string> Tags, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params)
{
    public bool Has(string tag) => Tags.Any(t => t == tag || t.StartsWith(tag + ":"));
    public string? TagValue(string tag) => Tags.FirstOrDefault(t => t.StartsWith(tag + ":"))?[(tag.Length + 1)..];
}

record ApiEnumValue(string Name, string RawValue, bool IsInt, string? Doc);

record ApiEnum(string Name, string? Doc, IReadOnlyList<ApiEnumValue> Values);

record ApiField(string Name, string Type, string? Doc);

record ApiStruct(string Name, string? Doc, IReadOnlyList<ApiField> Fields, IReadOnlyList<ApiSlot> Slots)
{
    public bool IsVtable => Slots.Count > 0;
}

record ApiFunction(string Name, string Returns, string? Doc, string? ReturnDoc, IReadOnlyList<ApiParam> Params);

class ApiModel
{
    public List<ApiEnum> Enums { get; } = [];
    public List<ApiStruct> Structs { get; } = [];   // includes vtables; use IsVtable to distinguish
    public List<ApiFunction> Functions { get; } = [];
}

static class ApiReader
{
    public static ApiModel Read(JsonObject root)
    {
        var m = new ApiModel();
        foreach (var eRaw in root["enums"]!.AsArray())
        {
            var e = eRaw!.AsObject();
            m.Enums.Add(new ApiEnum(Str(e, "name")!, Str(e, "doc"),
                e["values"]!.AsArray().Select(vRaw =>
                {
                    var v = vRaw!.AsObject();
                    var isInt = v["value"] is JsonValue jv && jv.TryGetValue<long>(out _);
                    return new ApiEnumValue(Str(v, "name")!,
                        isInt ? v["value"]!.GetValue<long>().ToString() : Str(v, "value")!,
                        isInt, Str(v, "doc"));
                }).ToList()));
        }

        void ReadStructLike(JsonObject o, bool vtable)
        {
            var slots = vtable
                ? o["slots"]!.AsArray().Select(s => ReadSlot(s!.AsObject())).ToList()
                : [];
            var fields = o["fields"]!.AsArray()
                .Select(fRaw => { var f = fRaw!.AsObject(); return new ApiField(Str(f, "name")!, Str(f, "type")!, Str(f, "doc")); })
                .ToList();
            m.Structs.Add(new ApiStruct(Str(o, "name")!, Str(o, "doc"), fields, slots));
        }

        foreach (var s in root["structs"]!.AsArray()) ReadStructLike(s!.AsObject(), vtable: false);
        foreach (var v in root["vtables"]!.AsArray()) ReadStructLike(v!.AsObject(), vtable: true);

        foreach (var f in root["functions"]!.AsArray())
        {
            var o = f!.AsObject();
            m.Functions.Add(new ApiFunction(Str(o, "name")!, Str(o, "returns")!, Str(o, "doc"), Str(o, "return_doc"),
                o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList()));
        }
        return m;
    }

    static ApiSlot ReadSlot(JsonObject o) => new(Str(o, "name")!, Str(o, "returns")!,
        o["tags"]?.AsArray().Select(t => t!.GetValue<string>()).ToList() ?? [], Str(o, "doc"),
        Str(o, "return_doc"), o["params"]!.AsArray().Select(p => ReadParam(p!.AsObject())).ToList());

    static ApiParam ReadParam(JsonObject o) => new(Str(o, "name"), Str(o, "type")!,
        o["tags"]!.AsArray().Select(t => t!.GetValue<string>()).ToList(), Str(o, "doc"));

    static string? Str(JsonObject o, string key) => o[key]?.GetValue<string>();
}

// =============================================================================
// -- §6.1 shared classification: what a slot MEANS, no C# yet ----------------
// =============================================================================

enum SlotShape { Fallible, ReturnsOutParam, TupleOutParams, Sequence, Plain }

record ClassifiedSlot(ApiSlot Slot, SlotShape Shape, bool Fallible, ApiParam? OutParam, ApiParam? SequenceParam,
    IReadOnlyList<ApiParam> OutParams, IReadOnlyList<ApiParam> PublicParams);

class ClassifiedModel
{
    public List<ApiStruct> Providers { get; } = [];
    public List<ApiStruct> Callbacks { get; } = [];
    public Dictionary<string, List<ClassifiedSlot>> SlotsByVtable { get; } = [];
    public Dictionary<string, List<ApiFunction>> FreeFunctionGroups { get; } = [];
    // ke_window's shape: no ke_X_create of its own (backend-agnostic — any
    // window backend hands back a ke_window_handle), plus two slots that must
    // run automatically rather than be called again by the consumer:
    // [lifecycle:init] once right after construction, [lifecycle:shutdown]
    // once right before destroy. Per vtable name.
    public Dictionary<string, string> LifecycleInit { get; } = [];
    public Dictionary<string, string> LifecycleShutdown { get; } = [];
}

static class Classifier
{
    public static ClassifiedModel Classify(ApiModel model, HashSet<string> explicitProviders,
        HashSet<string> explicitCallbacks)
    {
        var result = new ClassifiedModel();
        // ke_X_handle{ref, destroy} is a plain owner-wrapper, not something a
        // caller registers a provider/callback for in its own right — its
        // `destroy` slot is consumed inline by the owning provider's Dispose.
        var vtables = model.Structs.Where(s => s.IsVtable && !s.Name.EndsWith("_handle")).ToList();

        // A vtable is a callback type if some slot anywhere takes it BY VALUE
        // (not by pointer) with the [callback] tag — the caller implements it,
        // the engine invokes it, per ScriptingArchitectureV3 §4/§5.
        var callbackTypeNames = vtables
            .SelectMany(v => v.Slots).SelectMany(s => s.Params)
            .Where(p => p.Has("callback"))
            .Select(p => p.Type.Trim())
            .ToHashSet();
        callbackTypeNames.UnionWith(explicitCallbacks);

        foreach (var v in vtables)
        {
            if (callbackTypeNames.Contains(v.Name) && !explicitProviders.Contains(v.Name))
                result.Callbacks.Add(v);
            else
                result.Providers.Add(v);

            result.SlotsByVtable[v.Name] = v.Slots.Select(ClassifySlot).ToList();

            var init = v.Slots.FirstOrDefault(s => s.Has("lifecycle") && s.TagValue("lifecycle") == "init");
            if (init is not null) result.LifecycleInit[v.Name] = init.Name;
            var shutdown = v.Slots.FirstOrDefault(s => s.Has("lifecycle") && s.TagValue("lifecycle") == "shutdown");
            if (shutdown is not null) result.LifecycleShutdown[v.Name] = shutdown.Name;
        }

        // Free functions (not ke_X_create factories, which the provider's own
        // constructor already covers) are grouped by the type of their first
        // parameter — this is the ke_input_snapshot_is_key_down(snapshot, key)
        // shape: a value type with no vtable, so its ABI-side operations are
        // free functions rather than slots.
        //
        // A DIFFERENT shape (e.g. ke_console_sink_create() -> ke_logger_sink):
        // a plain factory function with no owning first-param at all, producing
        // a callback-vtable VALUE meant to be handed to some other slot (like
        // ke_logger.add_sink) rather than one it belongs to itself. Grouped by
        // its RETURN type instead, into the same FreeFunctionGroups bucket the
        // callback interface's file already gets rendered into.
        foreach (var fn in model.Functions)
        {
            if (fn.Name.EndsWith("_create") && fn.Params.Any(p => p.Type.Contains("ke_error"))
                && vtables.Any(v => fn.Returns.Contains(v.Name + "_handle")))
                continue; // factory function; the provider constructor handles it

            // Only group by first-param type when that type is one of OUR OWN
            // structs (a genuine value-type domain concept, e.g. ke_input_snapshot) —
            // not a bare C primitive (int32_t, float, ...), which ke_log_level_to_string's
            // single int param would otherwise misidentify as its "owner".
            var firstParamType = fn.Params.FirstOrDefault()?.Type.Replace("const ", "").Replace("struct ", "").TrimEnd('*', ' ');
            var owner = firstParamType is not null && model.Structs.Any(s => s.Name == firstParamType) ? firstParamType : null;
            owner ??= vtables.Select(v => v.Name).FirstOrDefault(n => fn.Returns.Trim() == n);
            if (owner is null) continue; // no known owner yet (e.g. ke_log_level_to_string) — not wired until something needs it
            (result.FreeFunctionGroups.TryGetValue(owner, out var list)
                ? list : result.FreeFunctionGroups[owner] = []).Add(fn);
        }

        return result;
    }

    static ClassifiedSlot ClassifySlot(ApiSlot slot)
    {
        var ps = slot.Params.ToList();
        var fallible = (slot.Returns is "_Bool" or "bool") && ps.Count > 0
            && ps[^1].Type.Replace(" ", "").Contains("ke_error**");
        if (fallible) ps = ps[..^1];

        var allOut = ps.Where(p => p.Has("out") && !p.Has("array_of")).ToList();
        var outParam = allOut.Count == 1 && ps.Count == 1 ? allOut[0] : null;
        var seqParam = ps.FirstOrDefault(p => p.Has("array_of"));

        // get_size(int32_t *width, int32_t *height, ke_error **out_error) shape:
        // more than one [out] parameter and nothing else public — a tuple return,
        // not a single value and not a sequence. Distinct from ReturnsOutParam
        // (exactly one [out] param, no siblings) purely by count.
        var tupleOut = allOut.Count >= 2 && allOut.Count == ps.Count ? allOut : null;

        var shape = outParam is not null ? SlotShape.ReturnsOutParam
            : tupleOut is not null ? SlotShape.TupleOutParams
            : seqParam is not null ? SlotShape.Sequence
            : fallible ? SlotShape.Fallible
            : SlotShape.Plain;

        return new ClassifiedSlot(slot, shape, fallible, outParam, seqParam, tupleOut ?? [], ps);
    }
}

// =============================================================================
// -- shared C-token -> C# idiom helpers ---------------------------------------
// =============================================================================

static class Idioms
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

    public static bool IsPointer(string cType) => cType.TrimEnd().EndsWith('*');

    public static string Deref(string cType) =>
        cType.Trim().Replace("const ", "").Replace("struct ", "").TrimEnd('*', ' ');

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

// =============================================================================
// -- §6.2 the C# backend: rendering the shared classification into C# idiom -
// =============================================================================

static class CSharpBackend
{
    const string Header = "// <auto-generated/>\n// Derived from ke_api.json. Do not edit; edit the C header instead.\n";

    static string XmlDoc(string indent, string? summary, IEnumerable<(string Name, string? Doc)>? pars = null,
        string? ret = null, bool throwsOnFail = false)
    {
        var lines = new List<string>();
        if (!string.IsNullOrEmpty(summary)) lines.Add($"{indent}/// <summary>{Escape(summary)}</summary>");
        foreach (var (n, d) in pars ?? [])
            if (!string.IsNullOrEmpty(d)) lines.Add($"{indent}/// <param name=\"{n}\">{Escape(d)}</param>");
        if (!string.IsNullOrEmpty(ret)) lines.Add($"{indent}/// <returns>{Escape(ret)}</returns>");
        if (throwsOnFail) lines.Add($"{indent}/// <exception cref=\"KernelError\">The native call failed.</exception>");
        return lines.Count > 0 ? string.Join('\n', lines) + '\n' : "";
    }

    static string Escape(string s) => s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;");

    /// The C# type an enum-tagged int becomes; enum name -> PascalCase type name.
    static string EnumTypeFor(ApiParam p) => Idioms.Pascal(p.TagValue("enum")![3..]);

    static string CsParamType(ApiModel model, ApiParam p)
    {
        var tagEnum = p.TagValue("enum");
        if (tagEnum is not null) return Idioms.StripPrefix(tagEnum);
        // A pointer to a struct this same ke_api.json declares renders as a C#
        // pointer to that (already in-namespace) struct; anything else falls
        // back to CsForeignType's normalization (still needs a --using if it's
        // cross-domain — same rule as the factory-parameter case).
        if (Idioms.IsPointer(p.Type))
            return Idioms.Deref(p.Type) + "*";
        return Idioms.CsPrimitive(p.Type);
    }

    // -------------------------------------------------------------- enums

    public static string RenderEnums(ApiModel model, string ns)
    {
        var o = new List<string> { Header, $"namespace {ns};\n" };
        foreach (var e in model.Enums)
        {
            o.Add(e.Doc is not null
                ? XmlDoc("", e.Doc).TrimEnd()
                : $"/// <summary>Mirrors <c>{e.Name}</c>.</summary>");
            o.Add($"public enum {Idioms.StripPrefix(e.Name)}");
            o.Add("{");
            foreach (var v in e.Values)
            {
                if (!string.IsNullOrEmpty(v.Doc)) o.Add($"    /// <summary>{Escape(v.Doc)}</summary>");
                var name = Idioms.EnumMember(v.Name, e.Name);
                var val = v.IsInt ? v.RawValue : Idioms.EnumMember(v.RawValue, e.Name);
                o.Add($"    {name} = {val},");
            }
            o.Add("}");
            o.Add("");
        }
        return string.Join('\n', o);
    }

    // ------------------------------------------------------------ provider

    public static string RenderProvider(ApiModel model, ApiStruct vtable, ClassifiedModel classified,
        string ns, string nativeNs, IReadOnlyList<string> extraUsings)
    {
        var typeName = Idioms.StripPrefix(vtable.Name);
        var slots = classified.SlotsByVtable[vtable.Name];
        var factory = model.Functions.FirstOrDefault(f => f.Name == vtable.Name + "_create");

        var o = new List<string>
        {
            Header,
            "using System.Runtime.CompilerServices;", // CallConvCdecl, needed whenever a slot has a [callback] param
            "using System.Runtime.InteropServices;",
            "using KernelEngine.Common;",
            "using KernelEngine.Common.Native;",
            $"using {nativeNs};",
        };
        foreach (var u in extraUsings) o.Add($"using {u};");
        o.Add("");
        o.Add($"namespace {ns};");
        o.Add("");

        // The INativeX{ ke_x* Native } accessor is this project's sanctioned
        // cross-domain composition mechanism (see ScriptingArchitectureV3.md
        // Appendix A.1's second correction): InternalsVisibleTo is banned
        // because it forces the producer to enumerate every consumer, the
        // inversion of the inversion this project's DI doctrine forbids. A
        // public Native accessor lets any consumer opt in without the producer
        // knowing who they are. Already load-bearing, hand-written, and
        // identical in shape across a dozen domains (INativeLogger,
        // INativeWindow, ...) before kabic existed — generating it here just
        // stops it being copy-pasted per domain.
        var nativeIface = "INative" + typeName;
        o.Add($"/// <summary>Exposes the raw native {typeName.ToLowerInvariant()} pointer for cross-domain composition wiring.</summary>");
        o.Add($"public unsafe interface {nativeIface}");
        o.Add("{");
        o.Add($"    {vtable.Name}* Native {{ get; }}");
        o.Add("}");
        o.Add("");

        o.Add(XmlDoc("", vtable.Doc).TrimEnd());
        o.Add($"public sealed unsafe partial class {typeName} : IDisposable, {nativeIface}");
        o.Add("{");
        o.Add($"    private {vtable.Name}* _native;");
        o.Add($"    private readonly delegate* unmanaged[Cdecl]<{vtable.Name}*, void> _destroy;");
        o.Add("");
        o.Add($"    private {vtable.Name}* Handle => _native != null ? _native");
        o.Add($"        : throw new ObjectDisposedException(nameof({typeName}));");
        o.Add("");
        o.Add($"    {vtable.Name}* {nativeIface}.Native => Handle;");
        o.Add("");

        classified.LifecycleInit.TryGetValue(vtable.Name, out var initSlot);
        classified.LifecycleShutdown.TryGetValue(vtable.Name, out var shutdownSlot);
        var initCall = initSlot is not null
            ? $"        {{ ke_error* err2 = null; KernelError.ThrowIfFailed(_native->{initSlot}(_native, &err2), err2, \"{initSlot}\"); }}"
            : null;

        var handleType = vtable.Name + "_handle";
        var hasHandleType = model.Structs.Any(s => s.Name == handleType);

        if (factory is not null)
        {
            var fparams = factory.Params.Where(p => !p.Type.Contains("ke_error")).ToList();
            var sig = string.Join(", ", fparams.Select(p => $"{Idioms.CsForeignType(p.Type)} {Idioms.Ident(p.Name!)}"));
            var call = string.Join(", ", fparams.Select(p => Idioms.Ident(p.Name!)));
            o.Add(XmlDoc("    ", factory.Doc, fparams.Select(p => (Idioms.Ident(p.Name!), p.Doc)),
                throwsOnFail: true).TrimEnd());
            // internal only when a param is a raw pointer from a sibling native
            // layer that a managed caller cannot supply without an unsafe
            // context (the hand-written idiom partial then exposes a public
            // constructor form instead). A factory with no such param — often
            // zero params at all, like ke_logger_create() — has nothing to hide
            // and stays public directly; no idiom wrapper needed.
            var needsIdiomWrapper = fparams.Any(p => Idioms.IsPointer(p.Type));
            o.Add($"    {(needsIdiomWrapper ? "internal" : "public")} {typeName}({sig})");
            o.Add("    {");
            o.Add("        ke_error* err = null;");
            o.Add($"        var handle = {nativeNs}.NativeMethods.{StripKe(factory.Name)}({(call.Length > 0 ? call + ", " : "")}&err);");
            o.Add($"        if (handle.@ref == null) throw KernelError.FromNative(err, \"{factory.Name}\");");
            o.Add("        _native = handle.@ref;");
            o.Add("        _destroy = handle.destroy;");
            if (initCall is not null) o.Add(initCall);
            o.Add("    }");
            o.Add("");
        }
        else if (hasHandleType)
        {
            // ke_window's shape: no factory of its own — any backend (GLFW, ...)
            // hands back a ke_window_handle, and construction is generic over
            // that handle rather than tied to one specific creator function.
            // Public, unlike the factory ctor above: a ke_X_handle is a plain
            // managed-visible value type this wrapper itself owns the shape of,
            // not a raw pointer into a sibling native namespace — any assembly
            // holding a valid handle (from calling a backend's own factory) can
            // legitimately construct the wrapper directly.
            o.Add($"    /// <summary>Wraps an owner <c>{handleType}</c> and runs {typeName.ToLowerInvariant()}'s startup lifecycle hook.</summary>");
            if (initCall is not null) o.Add("    /// <exception cref=\"KernelError\">The native call failed.</exception>");
            o.Add($"    public {typeName}({handleType} handle)");
            o.Add("    {");
            o.Add("        _native = handle.@ref;");
            o.Add("        _destroy = handle.destroy;");
            if (initCall is not null) o.Add(initCall);
            o.Add("    }");
            o.Add("");
        }

        foreach (var cs in slots)
        {
            // [sink]: a backend-facing event callback (e.g. ke_input.on_key), not
            // game-facing API. [lifecycle:*]: invoked automatically below, not
            // meant to be called again by the consumer.
            if (cs.Slot.Has("sink") || cs.Slot.Has("lifecycle")) continue;
            if (cs.PublicParams.Any(p => classified.Callbacks.Any(c => c.Name == p.Type.Trim())))
            {
                RenderCallbackMethod(o, vtable, cs, classified, typeName);
                continue;
            }
            RenderSlotMethod(model, o, cs);
        }

        o.Add($"    /// <summary>Releases the native {typeName.ToLowerInvariant()}.</summary>");
        o.Add("    public void Dispose()");
        o.Add("    {");
        o.Add("        if (_native == null) return;");
        if (shutdownSlot is not null)
            o.Add($"        _native->{shutdownSlot}(_native, null);");
        o.Add("        _destroy(_native);");
        o.Add("        _native = null;");
        o.Add("    }");
        o.Add("}");
        o.Add("");
        return string.Join('\n', o);
    }

    static void RenderSlotMethod(ApiModel model, List<string> o, ClassifiedSlot cs)
    {
        var slot = cs.Slot;
        var name = Idioms.Pascal(slot.Name);

        switch (cs.Shape)
        {
            case SlotShape.ReturnsOutParam:
            {
                var ret = Idioms.Deref(cs.OutParam!.Type);
                o.Add(XmlDoc("    ", slot.Doc, ret: slot.ReturnDoc, throwsOnFail: cs.Fallible).TrimEnd());
                o.Add($"    public {ret} {name}()");
                o.Add("    {");
                o.Add($"        {ret} result;");
                if (cs.Fallible)
                {
                    o.Add("        ke_error* err = null;");
                    o.Add($"        KernelError.ThrowIfFailed(Handle->{slot.Name}(Handle, &result, &err), err, \"{slot.Name}\");");
                }
                else
                {
                    o.Add($"        Handle->{slot.Name}(Handle, &result);");
                }
                o.Add("        return result;");
                o.Add("    }");
                o.Add("");
                return;
            }
            case SlotShape.TupleOutParams:
            {
                // e.g. ke_window.get_size(int32_t *width, int32_t *height, ke_error**)
                // -> (int Width, int Height) GetSize() — a tuple return, not a Span
                // (the values are independent scalars, not a homogeneous sequence).
                var names = cs.OutParams.Select(p => Idioms.Pascal(p.Name!)).ToList();
                var types = cs.OutParams.Select(p => Idioms.CsPrimitive(Idioms.Deref(p.Type))).ToList();
                var retTuple = string.Join(", ", types.Zip(names, (t, n) => $"{t} {n}"));
                var locals = cs.OutParams.Select(p => Idioms.Ident(p.Name!)).ToList();
                var callArgs = string.Concat(locals.Select(n => $", &{n}"));

                o.Add(XmlDoc("    ", slot.Doc, throwsOnFail: cs.Fallible).TrimEnd());
                o.Add($"    public ({retTuple}) {name}()");
                o.Add("    {");
                foreach (var (t, n) in types.Zip(locals)) o.Add($"        {t} {n};");
                if (cs.Fallible)
                {
                    o.Add("        ke_error* err = null;");
                    o.Add($"        KernelError.ThrowIfFailed(Handle->{slot.Name}(Handle{callArgs}, &err), err, \"{slot.Name}\");");
                }
                else
                {
                    o.Add($"        Handle->{slot.Name}(Handle{callArgs});");
                }
                o.Add($"        return ({string.Join(", ", locals)});");
                o.Add("    }");
                o.Add("");
                return;
            }
            case SlotShape.Sequence:
            {
                var elem = Idioms.Deref(cs.SequenceParam!.Type);
                var pname = Idioms.Ident(cs.SequenceParam!.Name!);
                var otherArgs = cs.PublicParams.Where(p => p != cs.SequenceParam).ToList();
                var extra = string.Concat(otherArgs.Select(p => $", (uint){pname}.Length"));
                o.Add(XmlDoc("    ", slot.Doc, [(pname, cs.SequenceParam.Doc)], slot.ReturnDoc).TrimEnd());
                o.Add($"    public int {name}Raw(Span<{elem}> {pname})");
                o.Add("    {");
                o.Add($"        fixed ({elem}* p = {pname})");
                o.Add($"            return (int)Handle->{slot.Name}(Handle, p{extra});");
                o.Add("    }");
                o.Add("");
                return;
            }
            case SlotShape.Fallible:
            {
                var args = cs.PublicParams;
                var sig = string.Join(", ", args.Select(p => $"{CsParamType(model, p)} {Idioms.Ident(p.Name!)}"));
                var call = string.Concat(args.Select(p => ", " + CallArg(p)));
                o.Add(XmlDoc("    ", slot.Doc, args.Select(p => (Idioms.Ident(p.Name!), p.Doc)),
                    slot.ReturnDoc, throwsOnFail: true).TrimEnd());
                o.Add($"    public void {name}({sig})");
                o.Add("    {");
                o.Add("        ke_error* err = null;");
                o.Add($"        KernelError.ThrowIfFailed(Handle->{slot.Name}(Handle{call}, &err), err, \"{slot.Name}\");");
                o.Add("    }");
                o.Add("");
                return;
            }
            default:
            {
                var args = cs.PublicParams;
                var sig = string.Join(", ", args.Select(p => $"{CsParamType(model, p)} {Idioms.Ident(p.Name!)}"));
                var call = string.Concat(args.Select(p => ", " + CallArg(p)));
                var retType = slot.Returns == "ke_bool" ? "bool" : Idioms.CsPrimitive(slot.Returns);
                var needsCast = retType == "nint"; // CsPrimitive maps `void *` -> nint; the raw call still returns void*
                o.Add(XmlDoc("    ", slot.Doc, args.Select(p => (Idioms.Ident(p.Name!), p.Doc)), slot.ReturnDoc).TrimEnd());
                o.Add($"    public {retType} {name}({sig})");
                o.Add("    {");
                if (slot.Returns == "ke_bool")
                    o.Add($"        return Handle->{slot.Name}(Handle{call}) != 0;");
                else if (retType == "void")
                    o.Add($"        Handle->{slot.Name}(Handle{call});");
                else if (needsCast)
                    o.Add($"        return (nint)Handle->{slot.Name}(Handle{call});");
                else
                    o.Add($"        return Handle->{slot.Name}(Handle{call});");
                o.Add("    }");
                o.Add("");
                return;
            }
        }

        string CallArg(ApiParam p) => p.Has("enum") ? $"({Idioms.CsPrimitive(p.Type)}){Idioms.Ident(p.Name!)}" : Idioms.Ident(p.Name!);
    }

    // ----------------------------------------------------- callback slot

    static void RenderCallbackMethod(List<string> o, ApiStruct vtable, ClassifiedSlot cs,
        ClassifiedModel classified, string ownerType)
    {
        var slot = cs.Slot;
        var cbParam = cs.PublicParams.First(p => classified.Callbacks.Any(c => c.Name == p.Type.Trim()));
        var cbType = classified.Callbacks.First(c => c.Name == cbParam.Type.Trim());
        var ifaceName = "I" + Idioms.StripPrefix(cbType.Name) + "Native";
        var hasLevel = cbType.Fields.Any(f => f.Name == "min_level");
        var handlesField = $"_{Idioms.Camel(slot.Name)}Handles";
        var otherParams = cs.PublicParams.Where(p => p != cbParam).ToList();

        o.Add(XmlDoc("    ", slot.Doc, [(Idioms.Ident(cbParam.Name!), cbParam.Doc)], throwsOnFail: true).TrimEnd());
        o.Add($"    // Roots each managed callback implementation for as long as native code");
        o.Add($"    // holds a pointer to it; released by the destroy trampoline below.");
        o.Add($"    private readonly List<GCHandle> {handlesField} = [];");
        o.Add("");
        var lvlArg = hasLevel ? ", int minLevel = 0" : "";
        var otherArgs = string.Concat(otherParams.Select(p => $", {CsParamType2(p)} {Idioms.Ident(p.Name!)}"));
        o.Add($"    public void {Idioms.Pascal(slot.Name)}({ifaceName} {Idioms.Ident(cbParam.Name!)}{otherArgs}{lvlArg})");
        o.Add("    {");
        o.Add($"        var gch = GCHandle.Alloc({Idioms.Ident(cbParam.Name!)});");
        o.Add($"        {handlesField}.Add(gch);");
        o.Add($"        var native = new {cbType.Name}");
        o.Add("        {");
        o.Add("            handle = GCHandle.ToIntPtr(gch).ToPointer(),");
        if (hasLevel) o.Add("            min_level = minLevel,");
        foreach (var s in cbType.Slots)
            o.Add($"            {s.Name} = &{Idioms.Pascal(s.Name)}Trampoline,");
        o.Add("        };");
        o.Add("        ke_error* err = null;");
        var extraCall = string.Concat(otherParams.Select(p => ", " + Idioms.Ident(p.Name!)));
        o.Add($"        KernelError.ThrowIfFailed(Handle->{slot.Name}(Handle, native{extraCall}, &err), err, \"{slot.Name}\");");
        o.Add("    }");
        o.Add("");

        // A second overload, forwarding an already-built value straight through
        // with no GCHandle/trampoline wrapping: for a callback-vtable VALUE that
        // came from a native value-factory (e.g. ke_console_sink_create(), see
        // ClassifiedModel.FreeFunctionGroups) rather than a managed
        // implementation of the interface above.
        var cbParamCsType = Idioms.Deref(cbParam.Type);
        o.Add($"    /// <summary>{slot.Doc} Takes an already-built <c>{cbType.Name}</c> value directly — for one produced by a native factory, not a managed <see cref=\"{ifaceName}\"/>.</summary>");
        o.Add(XmlDoc("    ", null, otherParams.Select(p => (Idioms.Ident(p.Name!), p.Doc)), throwsOnFail: true).TrimEnd());
        o.Add($"    public void {Idioms.Pascal(slot.Name)}Raw({cbParamCsType} {Idioms.Ident(cbParam.Name!)}{otherArgs})");
        o.Add("    {");
        o.Add("        ke_error* err = null;");
        o.Add($"        KernelError.ThrowIfFailed(Handle->{slot.Name}(Handle, {Idioms.Ident(cbParam.Name!)}{extraCall}, &err), err, \"{slot.Name}\");");
        o.Add("    }");
        o.Add("");

        foreach (var s in cbType.Slots)
        {
            var trampParams = s.Params.Select(p =>
                (Idioms.IsPointer(p.Type) ? $"{Idioms.Deref(p.Type)}*" : Idioms.CsPrimitive(p.Type)) + " " + Idioms.Ident(p.Name!));
            var sig = string.Join(", ", new[] { $"{cbType.Name}* self" }.Concat(trampParams));
            o.Add("    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]");
            o.Add($"    private static {Idioms.CsPrimitive(s.Returns)} {Idioms.Pascal(s.Name)}Trampoline({sig})");
            o.Add("    {");
            if (s.Name == "destroy")
            {
                o.Add("        GCHandle.FromIntPtr((nint)self->handle).Free();");
            }
            else
            {
                var callArgs = string.Concat(s.Params.Select(p =>
                    ", " + (Idioms.IsPointer(p.Type) ? $"in *{Idioms.Ident(p.Name!)}" : Idioms.Ident(p.Name!))));
                o.Add($"        var target = ({ifaceName})GCHandle.FromIntPtr((nint)self->handle).Target!;");
                o.Add($"        target.{Idioms.Pascal(s.Name)}({callArgs.TrimStart(',', ' ')});");
            }
            o.Add("    }");
            o.Add("");
        }

        string CsParamType2(ApiParam p) => p.Has("enum") ? Idioms.StripPrefix(p.TagValue("enum")!) : Idioms.CsPrimitive(p.Type);
    }

    public static string RenderCallbackInterface(ApiStruct cbType, string ns, string nativeNs)
    {
        var ifaceName = "I" + Idioms.StripPrefix(cbType.Name) + "Native";
        var owned = cbType.Slots.Where(s => s.Name != "destroy").ToList();

        var o = new List<string>
        {
            Header,
            $"using {nativeNs};",
            "",
            $"namespace {ns};",
            "",
        };
        o.Add(XmlDoc("", cbType.Doc).TrimEnd());
        o.Add($"public unsafe interface {ifaceName}");
        o.Add("{");
        foreach (var s in owned)
        {
            o.Add(XmlDoc("    ", s.Doc).TrimEnd());
            var ps = string.Join(", ", s.Params.Select(p =>
                (Idioms.IsPointer(p.Type) ? $"in {Idioms.Deref(p.Type)}" : Idioms.CsPrimitive(p.Type)) + " " + Idioms.Ident(p.Name!)));
            o.Add($"    {Idioms.CsPrimitive(s.Returns)} {Idioms.Pascal(s.Name)}({ps});");
        }
        o.Add("}");
        o.Add("");
        return string.Join('\n', o);
    }

    // -------------------------------------------------------- free functions

    public static string RenderFreeFunctions(string owner, List<ApiFunction> fns, string ns, string nativeNs, string libraryName)
    {
        var ownerCs = Idioms.StripPrefix(owner);
        var prefix = owner + "_";

        var o = new List<string>
        {
            Header,
            "using System.Runtime.InteropServices;",
            "",
            $"namespace {ns};",
            "",
            $"/// <summary>Free-function operations on <see cref=\"{owner}\"/>.</summary>",
            $"public static unsafe class {ownerCs}",
            "{",
        };

        // Two shapes share this file: an operation ON a value type (self is the
        // group's own owner, taken `in`/by-ref — ke_input_snapshot_is_key_down),
        // and a plain factory producing one BY VALUE with no owner param at all
        // (ke_console_sink_create() -> ke_logger_sink). Told apart by whether
        // the function's first param (if any) actually IS the owner type.
        bool HasSelf(ApiFunction f) => f.Params.Count > 0 && Idioms.Deref(f.Params[0].Type) == owner;

        foreach (var f in fns)
        {
            var hasSelf = HasSelf(f);
            var self = hasSelf ? f.Params[0] : null;
            var rest = hasSelf ? f.Params.Skip(1).ToList() : f.Params;
            // Not every value-factory function follows the {owner}_{verb} naming
            // convention (ke_console_sink_create doesn't start with ke_logger_sink_);
            // fall back to stripping the generic ke_ prefix so it still reads as a
            // method name instead of repeating the whole C symbol.
            var strippedName = f.Name.StartsWith(prefix) ? f.Name[prefix.Length..]
                : f.Name.StartsWith("ke_") ? f.Name[3..] : f.Name;
            var methodName = Idioms.Pascal(strippedName);
            var sig = string.Join(", ", rest.Select(p =>
                (p.Has("enum") ? Idioms.StripPrefix(p.TagValue("enum")!) : Idioms.CsPrimitive(p.Type)) + " " + Idioms.Ident(p.Name!)));
            var call = string.Concat(rest.Select(p => ", " + (p.Has("enum") ? $"(int){Idioms.Ident(p.Name!)}" : Idioms.Ident(p.Name!))));
            var retType = f.Returns == "ke_bool" ? "bool" : Idioms.CsPrimitive(f.Returns);
            var selfSig = self is not null ? $"in {Idioms.Deref(self.Type)} {Idioms.Ident(self.Name!)}" : null;
            var fullSig = string.Join(", ", new[] { selfSig }.Where(s => s is not null).Append(sig).Where(s => s!.Length > 0));

            o.Add(XmlDoc("    ", f.Doc, rest.Select(p => (Idioms.Ident(p.Name!), p.Doc))).TrimEnd());
            o.Add($"    public static {retType} {methodName}({fullSig})");
            o.Add("    {");
            if (self is not null)
            {
                o.Add($"        fixed ({Idioms.Deref(self.Type)}* p = &{Idioms.Ident(self.Name!)})");
                o.Add((f.Returns == "ke_bool" ? $"            return Native.{f.Name}(p{call}) != 0;"
                                               : $"            return Native.{f.Name}(p{call});"));
            }
            else
            {
                var call2 = string.Join(", ", rest.Select(p => p.Has("enum") ? $"(int){Idioms.Ident(p.Name!)}" : Idioms.Ident(p.Name!)));
                o.Add((f.Returns == "ke_bool" ? $"        return Native.{f.Name}({call2}) != 0;"
                                               : $"        return Native.{f.Name}({call2});"));
            }
            o.Add("    }");
            o.Add("");
        }

        // Declared directly here (not via the ClangSharp-generated NativeMethods,
        // which only covers what the .rsp knew about at its last regen) so these
        // stay in sync with ke_api.json without waiting on a separate binding run.
        o.Add("    private static unsafe class Native");
        o.Add("    {");
        foreach (var f in fns)
        {
            var hasSelf = HasSelf(f);
            var rest = (hasSelf ? f.Params.Skip(1) : f.Params)
                .Select(p => $"{(p.Has("enum") ? "int" : Idioms.CsPrimitive(p.Type))} {Idioms.Ident(p.Name!)}").ToList();
            var selfParamSig = hasSelf ? $"{Idioms.Deref(f.Params[0].Type)}* {Idioms.Ident(f.Params[0].Name!)}" : null;
            var nativeSig = string.Join(", ", (selfParamSig is not null ? [selfParamSig] : Array.Empty<string>()).Concat(rest));
            o.Add($"        [DllImport(\"{libraryName}\", CallingConvention = CallingConvention.Cdecl,");
            o.Add($"                   EntryPoint = \"{f.Name}\", ExactSpelling = true)]");
            o.Add($"        public static extern {(f.Returns == "ke_bool" ? "byte" : Idioms.CsPrimitive(f.Returns))} {f.Name}({nativeSig});");
            o.Add("");
        }
        o.Add("    }");
        o.Add("}");
        o.Add("");
        return string.Join('\n', o);
    }

    static string StripKe(string factoryName) => factoryName.StartsWith("ke_") ? factoryName[3..] : factoryName;
}

