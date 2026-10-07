using System.Text.RegularExpressions;

namespace Kabic.Numerics;

/// <summary>
/// Vectors, quaternions and matrices. A header declares them: a struct of two to four floats tagged
/// <c>[vector]</c> or <c>[quaternion]</c>, a struct of sixteen floats tagged <c>[matrix]</c>, a bare
/// <c>float[2..4]</c>, and a run of parameters tagged <c>[vector2:name]</c> or <c>[vector3:name]</c>. C# spells
/// them with <c>System.Numerics</c>, which the .NET base library already provides.
/// </summary>
public sealed class NumericsPack : IShapePack
{
    /// <summary>The kinds this pack recognises.</summary>
    public const string Vector = "vector", Quaternion = "quaternion", Matrix = "matrix";

    static readonly string[] LaneNames = ["x", "y", "z", "w"];
    static readonly Regex FloatArray = new(@"^float\s*\[(\d+)\]$", RegexOptions.Compiled);

    public TypeShape? Recognize(ApiModel model, string cType)
    {
        var type = cType.Replace("const ", "").Replace("struct ", "").Trim();

        if (FloatArray.Match(type) is { Success: true } array && int.Parse(array.Groups[1].Value) is >= 2 and <= 4 and var n)
            return new TypeShape(Vector, LaneNames[..n]);

        var s = model.Structs.FirstOrDefault(x => x.Name == type && !x.IsVtable);
        if (s is null) return null;

        if (s.Tags.Contains("matrix") && s.Fields is [{ } only] && FloatArray.Match(only.Type.Trim()) is { Success: true } m
            && m.Groups[1].Value == "16")
            return new TypeShape(Matrix, []);

        var kind = s.Tags.Contains("quaternion") ? Quaternion : s.Tags.Contains("vector") ? Vector : null;
        if (kind is null || s.Fields.Count is < 2 or > 4 || s.Fields.Any(f => f.Type.Trim() != "float")) return null;
        return new TypeShape(kind, s.Fields.Select(f => f.Name).ToArray());
    }

    public ParamGroup? GroupOf(ApiParam parameter)
    {
        var arity = parameter.Has("vector2") ? 2 : parameter.Has("vector3") ? 3 : 0;
        if (arity == 0) return null;
        var name = parameter.TagValue($"vector{arity}")
            ?? throw new InvalidOperationException(
                $"{parameter.Name}: [vector{arity}] must name the vector, as [vector{arity}:<name>]");
        return new ParamGroup(name, new TypeShape(Vector, LaneNames[..arity]));
    }

    public string? Project(string language, TypeShape shape) => (language, shape.Kind, shape.Lanes.Count) switch
    {
        (Languages.CSharp, Vector, 2 or 3 or 4) => $"Vector{shape.Lanes.Count}",
        (Languages.CSharp, Quaternion, 4) => "Quaternion",
        (Languages.CSharp, Matrix, _) => "Matrix4x4",
        (Languages.FieldTable, Vector, 2 or 3 or 4) => $"vec{shape.Lanes.Count}",
        (Languages.FieldTable, Quaternion, 4) => "quat",
        _ => null,
    };

    public IReadOnlyList<string> Imports(string language) => language == Languages.CSharp ? ["System.Numerics"] : [];

    public IReadOnlyList<string> Libraries(string language) => [];
}

/// <summary>Adds the numerics pack to a convention.</summary>
public static class NumericsExtensions
{
    /// <summary>Recognises vectors, quaternions and matrices.</summary>
    public static ConventionBuilder UseNumerics(this ConventionBuilder builder) => builder.Use(new NumericsPack());
}
