// kabic's middle-end (ScriptingArchitectureV3 §6.1): decides what a slot MEANS
// — fallible, owned, a sequence, a tuple, an enum, a callback, a lifecycle
// hook, how a provider gets built — from the description alone. Nothing here
// mentions a target language. A Lua/Python/Zig backend consumes the exact
// same ClassifiedModel a C# backend does, so two backends can never disagree
// on what a slot means, only on how they say it.

namespace Kabic;

public enum SlotShape { Fallible, ReturnsOutParam, TupleOutParams, Sequence, Plain }

public record ClassifiedSlot(ApiSlot Slot, SlotShape Shape, bool Fallible, ApiParam? OutParam, ApiParam? SequenceParam,
    IReadOnlyList<ApiParam> OutParams, IReadOnlyList<ApiParam> PublicParams);

// How a provider is built, decided once here so no backend re-derives it from
// raw factory/handle shapes: FromFactory (normal case — a ke_X_create exists;
// NeedsWrapper true when a param is a raw cross-domain pointer a managed
// caller can't supply unassisted), FromHandle (ke_window's shape: no factory
// of its own, built generically from a bare ke_X_handle another backend
// produced), or None (neither — nothing currently needs this, left unbuilt).
public enum ConstructorKind { FromFactory, FromHandle, None }

public record ConstructorPlan(ConstructorKind Kind, ApiFunction? Factory, string? HandleTypeName, bool NeedsWrapper);

// A free function's own "self" param, if it has one matching its group's
// owner type — resolved once instead of re-derived by every render pass that
// touches the function (a public wrapper method AND a raw DllImport today).
public record GroupedFunction(ApiFunction Fn, ApiParam? SelfParam);

public class ClassifiedModel
{
    public List<ApiStruct> Providers { get; } = [];
    public List<ApiStruct> Callbacks { get; } = [];
    public Dictionary<string, List<ClassifiedSlot>> SlotsByVtable { get; } = [];
    public Dictionary<string, List<GroupedFunction>> FreeFunctionGroups { get; } = [];
    public Dictionary<string, ConstructorPlan> Constructors { get; } = [];
    // Whether a callback vtable carries a `min_level` field, i.e. whether
    // AddSink-shaped methods get a minLevel parameter at all.
    public Dictionary<string, bool> CallbackHasLevel { get; } = [];
    // ke_window's shape: no ke_X_create of its own (backend-agnostic — any
    // window backend hands back a ke_window_handle), plus two slots that must
    // run automatically rather than be called again by the consumer:
    // [lifecycle:init] once right after construction, [lifecycle:shutdown]
    // once right before destroy. Per vtable name.
    public Dictionary<string, string> LifecycleInit { get; } = [];
    public Dictionary<string, string> LifecycleShutdown { get; } = [];
}

public static class Classifier
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

            result.CallbackHasLevel[v.Name] = v.Fields.Any(f => f.Name == "min_level");
        }

        // One constructor decision per provider, made once: prefer its own
        // ke_X_create factory; fall back to building generically from a bare
        // ke_X_handle when no factory exists (ke_window's shape); otherwise
        // there is nothing to construct it with yet.
        foreach (var v in result.Providers)
        {
            var factory = model.Functions.FirstOrDefault(f => f.Name == v.Name + "_create");
            if (factory is not null)
            {
                var fparams = factory.Params.Where(p => !p.Type.Contains("ke_error"));
                result.Constructors[v.Name] = new ConstructorPlan(ConstructorKind.FromFactory, factory, null,
                    NeedsWrapper: fparams.Any(p => CTypes.IsPointer(p.Type)));
                continue;
            }
            var handleType = v.Name + "_handle";
            result.Constructors[v.Name] = model.Structs.Any(s => s.Name == handleType)
                ? new ConstructorPlan(ConstructorKind.FromHandle, null, handleType, NeedsWrapper: false)
                : new ConstructorPlan(ConstructorKind.None, null, null, NeedsWrapper: false);
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
            var selfParam = firstParamType == owner ? fn.Params[0] : null;
            (result.FreeFunctionGroups.TryGetValue(owner, out var list)
                ? list : result.FreeFunctionGroups[owner] = []).Add(new GroupedFunction(fn, selfParam));
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
