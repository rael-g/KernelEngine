
namespace Kabic;

public enum SlotShape { Fallible, Try, ReturnsOutParam, TupleOutParams, Sequence, Plain }

/// <param name="SequenceParam">The pointer half of a pointer+count pair, if any.</param>
/// <param name="CountParam">
/// The count half named by <c>[array_of:name]</c> — it disappears from the public
/// signature (the sequence carries its own length) but is still passed natively.
/// </param>
/// <param name="OutParams">All <c>[out]</c> params other than a sequence, in declaration order.</param>
/// <param name="PublicParams">
/// Every parameter a caller still supplies: the trailing error out-param, and the
/// count paired with a sequence, are already removed.
/// </param>
public record ClassifiedSlot(ApiSlot Slot, SlotShape Shape, bool Fallible, ApiParam? OutParam, ApiParam? SequenceParam,
    ApiParam? CountParam, IReadOnlyList<ApiParam> OutParams, IReadOnlyList<ApiParam> PublicParams);

public enum ConstructorKind { FromFactory, FromHandle, None }

public record ConstructorPlan(ConstructorKind Kind, ApiFunction? Factory, string? HandleTypeName, bool NeedsWrapper);

public record GroupedFunction(ApiFunction Fn, ApiParam? SelfParam);

public class ClassifiedModel
{
    public List<ApiStruct> Providers { get; } = [];
    public List<ApiStruct> Callbacks { get; } = [];
    public Dictionary<string, List<ClassifiedSlot>> SlotsByVtable { get; } = [];
    public Dictionary<string, List<GroupedFunction>> FreeFunctionGroups { get; } = [];
    public Dictionary<string, ConstructorPlan> Constructors { get; } = [];
    public Dictionary<string, bool> CallbackHasLevel { get; } = [];
    public Dictionary<string, string> LifecycleInit { get; } = [];
    public Dictionary<string, string> LifecycleShutdown { get; } = [];
}

public static class Classifier
{
    public static ClassifiedModel Classify(ApiModel model, HashSet<string> explicitProviders,
        HashSet<string> explicitCallbacks, Convention convention)
    {
        var result = new ClassifiedModel();
        var vtables = model.Structs
            .Where(s => s.IsVtable && !s.External && !convention.IsHandleType(s.Name) && !convention.IsParamsType(s.Name))
            .ToList();

        var callbackTypeNames = vtables
            .SelectMany(v => v.Slots).SelectMany(s => s.Params)
            .Where(p => p.Has("callback"))
            .Select(p => p.Type.Trim())
            .ToHashSet();
        callbackTypeNames.UnionWith(explicitCallbacks);

        foreach (var v in vtables)
        {
            var isOwnable = model.Structs.Any(s => s.Name == convention.HandleTypeFor(v.Name))
                || model.Functions.Any(f => f.Name == convention.FactoryNameFor(v.Name));

            if (callbackTypeNames.Contains(v.Name) && !explicitProviders.Contains(v.Name))
                result.Callbacks.Add(v);
            else if (isOwnable || explicitProviders.Contains(v.Name))
                result.Providers.Add(v);

            result.SlotsByVtable[v.Name] = v.Slots.Select(s => ClassifySlot(s, convention)).ToList();

            var init = v.Slots.FirstOrDefault(s => s.Has("lifecycle") && s.TagValue("lifecycle") == "init");
            if (init is not null) result.LifecycleInit[v.Name] = init.Name;
            var shutdown = v.Slots.FirstOrDefault(s => s.Has("lifecycle") && s.TagValue("lifecycle") == "shutdown");
            if (shutdown is not null) result.LifecycleShutdown[v.Name] = shutdown.Name;

            result.CallbackHasLevel[v.Name] = v.Fields.Any(f => f.Name == "min_level");
        }

        foreach (var v in result.Providers)
        {
            var factory = model.Functions.FirstOrDefault(f => f.Name == convention.FactoryNameFor(v.Name));
            if (factory is not null)
            {
                var fparams = factory.Params.Where(p => !convention.IsErrorOutParam(p));
                result.Constructors[v.Name] = new ConstructorPlan(ConstructorKind.FromFactory, factory, null,
                    NeedsWrapper: fparams.Any(p => CTypes.IsPointer(p.Type)));
                continue;
            }
            var handleType = convention.HandleTypeFor(v.Name);
            result.Constructors[v.Name] = model.Structs.Any(s => s.Name == handleType)
                ? new ConstructorPlan(ConstructorKind.FromHandle, null, handleType, NeedsWrapper: false)
                : new ConstructorPlan(ConstructorKind.None, null, null, NeedsWrapper: false);
        }

        foreach (var fn in model.Functions)
        {
            if (convention.IsFactoryName(fn.Name) && fn.Params.Any(convention.IsErrorOutParam)
                && vtables.Any(v => fn.Returns.Contains(convention.HandleTypeFor(v.Name))))
                continue; // factory function; the provider constructor handles it

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

    static ClassifiedSlot ClassifySlot(ApiSlot slot, Convention convention)
    {
        var ps = slot.Params.ToList();
        var fallible = convention.IsFallible(slot.Returns, ps);
        if (fallible) ps = ps[..^1];

        var isTry = slot.Has("try");

        var seqParam = ps.FirstOrDefault(p => p.Has("array_of"));
        var countName = seqParam?.TagValue("array_of");
        var countParam = countName is not null ? ps.FirstOrDefault(p => p.Name == countName) : null;
        if (countParam is not null) ps = ps.Where(p => p != countParam).ToList();

        var allOut = ps.Where(p => p.Has("out") && !p.Has("array_of")).ToList();
        var outParam = allOut.Count == 1 ? allOut[0] : null;

        var tupleOut = allOut.Count >= 2 ? allOut : null;

        var shape = isTry ? SlotShape.Try
            : seqParam is not null ? SlotShape.Sequence
            : outParam is not null ? SlotShape.ReturnsOutParam
            : tupleOut is not null ? SlotShape.TupleOutParams
            : fallible ? SlotShape.Fallible
            : SlotShape.Plain;

        return new ClassifiedSlot(slot, shape, fallible, outParam, seqParam, countParam,
            isTry ? allOut : tupleOut ?? [], ps);
    }
}
