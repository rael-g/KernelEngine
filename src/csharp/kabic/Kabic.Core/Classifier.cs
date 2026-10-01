
namespace Kabic;

public enum SlotShape { Fallible, Try, ReturnsOutParam, TupleOutParams, Plain }

/// <summary>
/// A pointer+count pair: the pointer parameter carrying <c>[array_of:name]</c> and the
/// parameter it names. Carrying a sequence is a property of the parameter, not of the
/// slot — a slot may carry several, alongside a params bag and a closure.
/// </summary>
public record SequencePair(ApiParam Seq, ApiParam Count);

/// <summary>
/// An opaque-payload pair: the <c>void *</c> parameter carrying <c>[bytes_of:name]</c> and
/// the byte count it names. The two are one value the caller already holds as a type, so
/// the projection takes that type and derives the count from it -- left apart, the caller
/// supplies the address and the size of the same variable and nothing checks that the two
/// describe it.
/// </summary>
public record BlobPair(ApiParam Blob, ApiParam Size);

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

    /// <summary>
    /// The parameter the slot's returned pointer is counted by, when the return declares
    /// <c>[array_of:<name>]</c>. The two together are one value, so the caller supplies
    /// neither: the count leaves the signature and the return becomes a span. Left apart,
    /// every caller re-derives the same bounds from a pointer it was handed raw.
    /// </summary>
    public ApiParam? ReturnCount { get; init; }

    /// <summary>
    /// The <c>[out]</c> parameters of a slot that already answers, so none of them could
    /// become the return. They stay parameters, and the projection spells them <c>out</c>:
    /// left as the pointers the ABI takes, the caller declares the local and takes its
    /// address, which is the whole of what a binding is supposed to have stopped doing.
    /// </summary>
    public IReadOnlyList<ApiParam> TrailingOuts { get; init; } = [];

    /// <summary>
    /// The opaque payloads the slot takes, each with the byte count bounding it. The count
    /// leaves the signature the same way a sequence's does, and the payload is spelled as
    /// the caller's own type.
    /// </summary>
    public IReadOnlyList<BlobPair> Blobs { get; init; } = [];
}

public enum ConstructorKind { FromFactory, FromHandle, None }

public record ConstructorPlan(ConstructorKind Kind, ApiFunction? Factory, string? HandleTypeName, bool NeedsWrapper);

/// <param name="Classified">
/// What the function's own parameters and return declare, read with the same rules a
/// vtable slot's are. A free function is the same contract reached by a symbol instead of
/// a field, so a tag placed on one has to mean what it means on the other -- read twice,
/// the same header line would project two different ways.
/// </param>
public record GroupedFunction(ApiFunction Fn, ApiParam? SelfParam, ClassifiedSlot Classified);

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
                ? list : result.FreeFunctionGroups[owner] = []).Add(
                new GroupedFunction(fn, selfParam, ClassifySlot(model, AsSlot(fn, selfParam), convention)));
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

    /// <summary>
    /// A free function read as the slot it is, with the receiver dropped: the receiver is
    /// how the call reaches the contract, never part of what the contract answers, so
    /// leaving it in would let it be mistaken for a value the caller supplies.
    /// </summary>
    static ApiSlot AsSlot(ApiFunction fn, ApiParam? self) =>
        new(fn.Name, fn.Returns, [], fn.Doc, fn.ReturnDoc,
            (self is null ? fn.Params : fn.Params.Skip(1)).ToList())
        {
            ReturnTags = fn.ReturnTags,
        };

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

        var blobs = new List<BlobPair>();
        foreach (var blob in ps.Where(p => p.Has("bytes_of")))
        {
            if (!CTypes.IsPointer(blob.Type))
                throw new InvalidOperationException(
                    $"{slot.Name}.{blob.Name}: [bytes_of] bounds the bytes a pointer reaches, and "
                    + $"{blob.Type.Trim()} is not one");
            if (CTypes.Deref(blob.Type).Replace("const ", "").Trim() is not "void")
                throw new InvalidOperationException(
                    $"{slot.Name}.{blob.Name}: [bytes_of] is how an opaque payload names the type it "
                    + $"carries, and {blob.Type.Trim()} already names one -- a typed sequence is "
                    + "[array_of:] instead.");
            var sizeName = blob.TagValue("bytes_of");
            var size = ps.FirstOrDefault(p => p.Name == sizeName)
                ?? throw new InvalidOperationException(
                    $"{slot.Name}.{blob.Name}: [bytes_of:{sizeName}] names a byte-count parameter "
                    + "the slot does not declare");
            blobs.Add(new BlobPair(blob, size));
        }
        ps = ps.Where(p => blobs.All(b => b.Size != p)).ToList();

        ApiParam? returnCount = null;
        if (slot.ReturnTagValue("array_of") is { } returnCountName)
        {
            if (!CTypes.IsPointer(slot.Returns))
                throw new InvalidOperationException(
                    $"{slot.Name}: the return declares [array_of:{returnCountName}], and "
                    + $"{slot.Returns.Trim()} is not a pointer, so there is no sequence to bound");
            returnCount = ps.FirstOrDefault(p => p.Name == returnCountName)
                ?? throw new InvalidOperationException(
                    $"{slot.Name}: the return's [array_of:{returnCountName}] names a length "
                    + "parameter the slot does not declare");
            ps = ps.Where(p => p != returnCount).ToList();
        }

        var allOut = ps.Where(p => p.Has("out") && !p.Has("array_of")).ToList();

        foreach (var rooted in allOut.Where(p => p.Has("rooted")))
            if (rooted.Type.Replace(" ", "") is not "void**")
                throw new InvalidOperationException(
                    $"{slot.Name}.{rooted.Name}: [rooted] on a written-back parameter reads back the"
                    + " same opaque pointer the rooting side handed over, so the slot writes a"
                    + $" void ** -- {rooted.Type.Trim()} is a type the native side would have to"
                    + " dereference, and a rooted pointer is the one thing it never does.");

        var written = allOut.Concat(returnCount is null ? [] : new[] { returnCount }).ToList();
        var stripped = written.Where(p => p.Name!.StartsWith("out_", StringComparison.Ordinal)
                                       && p.Name!.Length > "out_".Length)
            .Select(p => (Param: p, Bare: p.Name!["out_".Length..])).ToList();
        foreach (var (p, bare) in stripped)
        {
            var taken = slot.Params.FirstOrDefault(q => q != p && q.Name == bare)
                ?? stripped.FirstOrDefault(other => other.Param != p && other.Bare == bare).Param;
            if (taken is not null)
                throw new InvalidOperationException(
                    $"{slot.Name}.{p.Name}: a written-back parameter is projected without the out_ that"
                    + $" only marked its direction, and {taken.Name} already answers to {bare}. Two"
                    + " parameters reaching the caller under one name is not something to resolve by"
                    + " picking one, so rename the declaration instead.");
        }

        var carriesReturn = slot.Returns.Trim() is not "void"
            && !convention.SignalsFailureByReturn(slot.Returns);
        var outParam = allOut.Count == 1 && !carriesReturn ? allOut[0] : null;

        var tupleOut = allOut.Count >= 2 ? allOut : null;

        var shape = isTry ? SlotShape.Try
            : outParam is not null ? SlotShape.ReturnsOutParam
            : tupleOut is not null ? SlotShape.TupleOutParams
            : fallible ? SlotShape.Fallible
            : SlotShape.Plain;

        var trailingOuts = shape is SlotShape.Plain or SlotShape.Fallible ? allOut : [];
        if (trailingOuts.Count > 0 && shape is SlotShape.Fallible)
            throw new InvalidOperationException(
                $"{slot.Name}: the slot answers, fails and writes {string.Join(", ", trailingOuts.Select(p => p.Name))}"
                + " -- three answers to one question. Which of them the caller reads first is not"
                + " something the header says, so the projection for it has to be chosen rather"
                + " than guessed at here.");

        if (blobs.Count > 0 && shape is not (SlotShape.Plain or SlotShape.Fallible))
            throw new InvalidOperationException(
                $"{slot.Name}: the slot takes an opaque payload and is projected as {shape}. The"
                + " payload is spelled as the caller's own type, which makes the method generic, and"
                + " how that reads alongside the rest of this shape is a choice rather than something"
                + " to infer from the header here.");

        return new ClassifiedSlot(slot, shape, fallible, outParam, sequences,
            isTry ? allOut : tupleOut ?? [], ps)
        {
            ExpandedParam = expanded,
            ExpandedStruct = bag,
            ReturnCount = returnCount,
            TrailingOuts = trailingOuts,
            Blobs = blobs,
        };
    }
}
