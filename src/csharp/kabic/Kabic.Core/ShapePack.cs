namespace Kabic;

/// <summary>The names kabic gives the targets a pack can project a shape into.</summary>
public static class Languages
{
    /// <summary>The managed projection.</summary>
    public const string CSharp = "csharp";

    /// <summary>The C table that describes a component's fields to the runtime.</summary>
    public const string FieldTable = "field-table";
}

/// <summary>What a pack recognised a C type as. <see cref="Kind"/> is the pack's own word; kabic does not interpret it.</summary>
public sealed record TypeShape(string Kind, IReadOnlyList<string> Lanes);

/// <summary>A run of consecutive parameters a pack groups into one value, and the name that value is given.</summary>
public sealed record ParamGroup(string Name, TypeShape Shape);

/// <summary>
/// A family of types that only some ABIs have and only some languages can spell: vectors, quaternions,
/// matrices. kabic itself knows none of them. A pack recognises them from what a header declares, projects them
/// into the languages it knows, and names what the generated code then needs; a language the pack knows nothing
/// of keeps the plain struct.
/// </summary>
public interface IShapePack
{
    /// <summary>The shape a C type is, or null when this pack does not recognise it.</summary>
    TypeShape? Recognize(ApiModel model, string cType);

    /// <summary>The shape a parameter opens when it is the first of several that spell one value, or null.</summary>
    ParamGroup? GroupOf(ApiParam parameter);

    /// <summary>How <paramref name="language"/> spells <paramref name="shape"/>, or null when it has no such type.</summary>
    string? Project(string language, TypeShape shape);

    /// <summary>
    /// What the generated code for <paramref name="language"/> has to import to spell the projections, in that
    /// language's own sense of the word: a namespace to <c>using</c> in C#, a header to <c>#include</c> in C++, a
    /// module to <c>@import</c> in Zig. The backend renders each in its own syntax.
    /// </summary>
    IReadOnlyList<string> Imports(string language);

    /// <summary>Libraries, beyond the language's own, the generated code for <paramref name="language"/> has to reference.</summary>
    IReadOnlyList<string> Libraries(string language);
}
