namespace Kabic;

/// <summary>
/// Which fields of a component struct a field table describes, the kind each is addressed as, and
/// the default each declares. Every language's table is written from these answers, so the tables
/// cannot come to disagree about a field.
/// </summary>
public static class FieldTables
{
    /// <summary>
    /// The structs a scene file can address: the domain's own component structs, in declaration
    /// order, that have at least one field <see cref="Describes"/> accepts.
    /// </summary>
    public static IEnumerable<ApiStruct> Describable(ApiModel model, Convention convention) =>
        model.Structs.Where(s => !s.IsVtable
            && !s.External
            && s.Name.EndsWith(convention.ComponentSuffix, StringComparison.Ordinal)
            && s.Fields.Any(f => Describes(model, f, convention)));

    /// <summary>The fields of <paramref name="s"/> its table describes, in declaration order.</summary>
    public static IEnumerable<ApiField> Fields(ApiModel model, ApiStruct s, Convention convention) =>
        s.Fields.Where(f => Describes(model, f, convention));

    /// <summary>The key a scene writes for the field.</summary>
    public static string KeyOf(ApiField f) => f.TagValue("name") ?? f.Name;

    /// <summary>
    /// Whether a scene file can address this field at all. <c>[output]</c> is a field a system
    /// writes every tick; describing it would invite a scene to author a value that is overwritten
    /// before anything reads it.
    /// </summary>
    public static bool Describes(ApiModel model, ApiField f, Convention convention) =>
        !f.Has("output") && KindOf(model, f, convention) is not null;

    /// <summary>
    /// The kind a field is addressed as, or null when the field has no scene-file spelling: a
    /// derived matrix or an opaque handle is produced by a system, never written down. C's own
    /// scalars and strings are kinds here; every other kind is what a pack projects the type to.
    /// </summary>
    public static string? KindOf(ApiModel model, ApiField f, Convention convention)
    {
        var table = convention.FieldTable!;
        if (f.Has("bool")) return "bool";
        var type = Base(f.Type);
        if (model.Enums.Any(e => e.Name == type)) return "int";
        if (convention.Project(Languages.FieldTable, model, type) is { } projected)
            return table.Variants.ContainsKey(projected) ? projected : null;
        return type switch
        {
            "float" or "double" => "float",
            "bool" or "_Bool" => "bool",
            "int8_t" or "int16_t" or "int32_t" or "int64_t" => "int",
            "uint8_t" or "uint16_t" or "uint32_t" or "uint64_t" => "int",
            "int" or "unsigned" or "unsigned int" => "int",
            var t when t.StartsWith("char[") => "string",
            _ => null,
        };
    }

    /// <summary>
    /// The field's <c>[default:]</c> split into its lanes, with its kind, or null when the header
    /// declares none. Fails when the number of lanes is not the one the field's kind takes.
    /// </summary>
    public static (string Kind, string Raw, string[] Lanes)? DefaultOf(ApiModel model, ApiField f, Convention convention)
    {
        var d = f.TagValue("default");
        if (d is null) return null;
        var kind = KindOf(model, f, convention)!;
        var parts = d.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var lanes = convention.ShapeOf(model, Base(f.Type))?.Shape.Lanes.Count ?? 1;
        if (parts.Length != lanes)
            throw new InvalidOperationException(
                $"{f.Name}: [default:{d}] has {parts.Length} components but {convention.FieldTable!.Variants[kind].Constant} takes {lanes}");
        return (kind, d, parts);
    }

    private static string Base(string cType) =>
        cType.Replace("const ", "").Replace("struct ", "").Trim();
}
