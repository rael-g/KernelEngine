
namespace Kabic;

public enum SlotShape { Fallible, Try, ReturnsOutParam, TupleOutParams, Plain }

/// <summary>
/// A pointer+count pair: the pointer parameter carrying <c>[array_of:name]</c> and the
/// parameter it names. Carrying a sequence is a property of the parameter, not of the
/// slot — a slot may carry several, alongside a params bag and a closure.
/// </summary>
public record SequencePair(ApiParam Seq, ApiParam Count);

/// <param name="OutParams">All <c>[out]</c> params other than a sequence, in declaration order.</param>
/// <param name="PublicParams">
/// Every parameter a caller still supplies: the trailing error out-param, and the
/// count paired with a sequence, are already removed. A parameter marked
/// <c>[expand]</c> has been replaced by one entry per field of the struct it points at.
/// </param>
public record ClassifiedSlot(ApiSlot Slot, SlotShape Shape, bool Fallible, ApiParam? OutParam,
    IReadOnlyList<SequencePair> Sequences,
    IReadOnlyList<ApiParam> OutParams, IReadOnlyList<ApiParam> PublicParams)
{
    /// <summary>The <c>[expand]</c> parameter, whose fields stand in for it in <see cref="PublicParams"/>.</summary>
    public ApiParam? ExpandedParam { get; init; }

    /// <summary>The struct <see cref="ExpandedParam"/> points at, whose fields the call has to rebuild.</summary>
    public ApiStruct? ExpandedStruct { get; init; }
}

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

            result.SlotsByVtable[v.Name] = v.Slots.Select(s => ClassifySlot(model, s, convention)).ToList();

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
                continue;

            var firstParamType = fn.Params.FirstOrDefault()?.Type.Replace("const ", "").Replace("struct ", "").TrimEnd('*', ' ');
            var owner = firstParamType is not null && model.Structs.Any(s => s.Name == firstParamType) ? firstParamType : null;
            owner ??= vtables.Select(v => v.Name).FirstOrDefault(n => fn.Returns.Trim() == n);
            if (owner is null) continue;
            var selfParam = firstParamType == owner ? fn.Params[0] : null;
            (result.FreeFunctionGroups.TryGetValue(owner, out var list)
                ? list : result.FreeFunctionGroups[owner] = []).Add(new GroupedFunction(fn, selfParam));
        }

        return result;
    }

    /// <summary>
    /// The <c>[expand]</c> parameter of a slot and the struct it points at, or a pair of
    /// nulls when the slot has none.
    /// </summary>
    public static (ApiParam? Param, ApiStruct? Bag) ExpandedBag(ApiModel model, ApiSlot slot)
    {
        var expanded = slot.Params.FirstOrDefault(p => p.Has("expand"));
        if (expanded is null) return (null, null);

        if (!CTypes.IsPointer(expanded.Type))
            throw new InvalidOperationException(
                $"{slot.Name}.{expanded.Name}: [expand] rebuilds a struct the call passes by "
                + $"reference, but {expanded.Type.Trim()} is not a pointer");

        var bagName = CTypes.Deref(expanded.Type).Trim()
            .Replace("const ", "").Replace("struct ", "").Trim();
        var bag = model.Structs.FirstOrDefault(s => s.Name == bagName)
            ?? throw new InvalidOperationException(
                $"{slot.Name}.{expanded.Name}: [expand] needs the fields of {bagName}, "
                + "and no struct by that name is described");
        return (expanded, bag);
    }

    static ClassifiedSlot ClassifySlot(ApiModel model, ApiSlot slot, Convention convention)
    {
        var ps = slot.Params.ToList();
        var fallible = convention.IsFallible(slot.Returns, ps);
        if (fallible) ps = ps[..^1];

        var (expanded, bag) = ExpandedBag(model, slot);
        if (expanded is not null)
            ps = ps.SelectMany(p => p == expanded
                ? bag!.Fields.Select(f => new ApiParam(f.Name, f.Type, f.Tags, f.Doc))
                : (IEnumerable<ApiParam>)[p]).ToList();

        var isTry = slot.Has("try");

        var sequences = new List<SequencePair>();
        foreach (var seq in ps.Where(p => p.Has("array_of")))
        {
            var countName = seq.TagValue("array_of");
            var count = ps.FirstOrDefault(p => p.Name == countName)
                ?? throw new InvalidOperationException(
                    $"{slot.Name}.{seq.Name}: [array_of:{countName}] names a length parameter "
                    + "the slot does not declare");
            sequences.Add(new SequencePair(seq, count));
        }
        ps = ps.Where(p => sequences.All(s => s.Count != p)).ToList();

        var allOut = ps.Where(p => p.Has("out") && !p.Has("array_of")).ToList();

        var carriesReturn = slot.Returns.Trim() is not "void"
            && !convention.SignalsFailureByReturn(slot.Returns);
        var outParam = allOut.Count == 1 && !carriesReturn ? allOut[0] : null;

        var tupleOut = allOut.Count >= 2 ? allOut : null;

        var shape = isTry ? SlotShape.Try
            : outParam is not null ? SlotShape.ReturnsOutParam
            : tupleOut is not null ? SlotShape.TupleOutParams
            : fallible ? SlotShape.Fallible
            : SlotShape.Plain;

        return new ClassifiedSlot(slot, shape, fallible, outParam, sequences,
            isTry ? allOut : tupleOut ?? [], ps)
        {
            ExpandedParam = expanded,
            ExpandedStruct = bag,
        };
    }
}
