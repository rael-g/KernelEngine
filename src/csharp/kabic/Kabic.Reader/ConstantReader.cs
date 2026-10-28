using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Kabic.Reader;

/// <summary>
/// Reads the constants a header defines as object-like macros. The preprocessor's expansion says
/// which macros hold a value; clang types each one through a probe declaration and folds an integer
/// through a probe enumerator, so a value is the one a C compiler computes.
/// </summary>
public static partial class ConstantReader
{
    /// <summary>The prefix of every probe declaration, followed by the macro's name.</summary>
    public const string ProbePrefix = "kabic_constant_";

    /// <summary>
    /// The object-like macros the headers define, in definition order, each with the doc comment
    /// written above it or after it.
    /// </summary>
    /// <param name="headers">Full paths of the headers that own the macros.</param>
    public static List<(string Name, string? Doc)> Candidates(IEnumerable<string> headers)
    {
        var found = new List<(string, string?)>();
        foreach (var header in headers)
        {
            var lines = File.ReadAllLines(header);
            for (var i = 0; i < lines.Length; i++)
            {
                if (ObjectLikeDefine().Match(lines[i]) is not { Success: true } m) continue;
                var name = m.Groups[1].Value;
                if (found.All(f => f.Item1 != name)) found.Add((name, DocOf(lines, i)));
            }
        }
        return found;
    }

    /// <summary>The line the preprocessor expands the macro <paramref name="name"/> on.</summary>
    public static string ExpansionProbe(string name) => $"{ProbePrefix}{name} {name}";

    /// <summary>
    /// The candidates whose expansion in <paramref name="preprocessed"/> can be a value: defined
    /// where the headers were read, not empty, and not an attribute.
    /// </summary>
    public static List<(string Name, string? Doc)> Valued(IReadOnlyList<(string Name, string? Doc)> candidates, string preprocessed)
    {
        var bodies = new Dictionary<string, string>();
        foreach (Match m in ExpansionLine().Matches(preprocessed)) bodies[m.Groups[1].Value] = m.Groups[2].Value.Trim();
        return candidates.Where(c => bodies.TryGetValue(c.Name, out var body) && body != c.Name && HoldsValue(body)).ToList();
    }

    static bool HoldsValue(string body) =>
        body.Length > 0 && !body.StartsWith("[[", StringComparison.Ordinal)
        && !body.StartsWith("__attribute__", StringComparison.Ordinal) && !body.StartsWith("__declspec", StringComparison.Ordinal);

    static string? DocOf(string[] lines, int at)
    {
        var trailing = lines[at].IndexOf("///<", StringComparison.Ordinal);
        if (trailing >= 0) return Words(lines[at][(trailing + 4)..]);

        var above = new List<string>();
        for (var i = at - 1; i >= 0; i--)
        {
            var t = lines[i].Trim();
            if (t.StartsWith("///", StringComparison.Ordinal)) above.Insert(0, t[3..]);
            else if (t.EndsWith("*/", StringComparison.Ordinal))
            {
                var block = new List<string>();
                for (var j = i; j >= 0; j--)
                {
                    var u = lines[j].Trim();
                    block.Insert(0, u);
                    if (u.StartsWith("/**", StringComparison.Ordinal)) { i = j; break; }
                    if (u.StartsWith("/*", StringComparison.Ordinal)) return null;
                }
                above.InsertRange(0, block.Select(u => u.Replace("/**", "").Replace("*/", "").TrimStart('*')));
                break;
            }
            else break;
        }
        return above.Count == 0 ? null : Words(string.Join(' ', above));
    }

    static string? Words(string text) =>
        string.Join(' ', text.Split((char[])[' ', '\t'], StringSplitOptions.RemoveEmptyEntries)) is { Length: > 0 } w ? w : null;

    /// <summary>The declaration that makes clang type the macro <paramref name="name"/>.</summary>
    public static string TypeProbe(string name) => $"static const __typeof__({name}) {ProbePrefix}{name} = {name};";

    /// <summary>
    /// The declaration that makes clang fold the integer macro <paramref name="name"/> as a
    /// value of <paramref name="type"/>.
    /// </summary>
    public static string ValueProbe(string name, string type) => $"enum : {type} {{ {ProbePrefix}{name} = {name} }};";

    /// <summary>
    /// What a type probe says of the candidates: <paramref name="Read"/> holds the strings and
    /// records, <paramref name="Integers"/> each integer with the type it is spelled as and the
    /// type a value probe folds it as, and <paramref name="Errors"/> the candidates that are
    /// neither. <paramref name="Order"/> is the candidates' definition order.
    /// </summary>
    public sealed record Typed(List<ApiConstant> Read,
        List<(string Name, string Spelled, string Underlying, string? Doc)> Integers, List<string> Errors, List<string> Order);

    /// <summary>
    /// Reads what the type probes of <paramref name="candidates"/> in <paramref name="ast"/> say.
    /// </summary>
    public static Typed ReadTypes(JsonObject ast, IReadOnlyList<(string Name, string? Doc)> candidates)
    {
        var top = ast["inner"]!.AsArray().OfType<JsonObject>().ToList();
        var probes = top.Where(n => n["kind"]?.GetValue<string>() == "VarDecl")
            .Where(n => n["name"]?.GetValue<string>()?.StartsWith(ProbePrefix, StringComparison.Ordinal) == true)
            .ToDictionary(n => n["name"]!.GetValue<string>()[ProbePrefix.Length..]);

        var read = new List<ApiConstant>();
        var integers = new List<(string, string, string, string?)>();
        var errors = new List<string>();
        foreach (var (name, doc) in candidates)
        {
            if (!probes.TryGetValue(name, out var probe) || probe["inner"]?.AsArray().OfType<JsonObject>().FirstOrDefault() is not { } init)
            {
                errors.Add($"{name}: clang declared no probe for the macro");
                continue;
            }
            var value = Stripped(init);
            var kind = value["kind"]?.GetValue<string>();
            var type = value["type"]?.AsObject();
            var spelled = type?["qualType"]?.GetValue<string>() ?? "";
            var underlying = type?["desugaredQualType"]?.GetValue<string>() ?? spelled;
            if (kind == "StringLiteral")
                read.Add(new ApiConstant(name, "const char *", value["value"]!.GetValue<string>(), null, doc));
            else if (kind == "CompoundLiteralExpr" && Members(top, spelled) is { } members
                     && Literals(value) is { } literals && literals.Count == members.Count)
                read.Add(new ApiConstant(name, spelled, null, members.Zip(literals, (m, l) => new ApiConstantField(m, l)).ToList(), doc));
            else if (IsInteger(underlying))
                integers.Add((name, spelled, underlying, doc));
            else
                errors.Add($"{name}: a macro of type {spelled} is not a constant kabic can describe");
        }
        return new Typed(read, integers, errors, [.. candidates.Select(c => c.Name)]);
    }

    /// <summary>The values a value probe folded, keyed by macro name.</summary>
    public static Dictionary<string, string> ReadValues(JsonObject ast) =>
        ast["inner"]!.AsArray().OfType<JsonObject>()
            .Where(n => n["kind"]?.GetValue<string>() == "EnumDecl")
            .SelectMany(n => (n["inner"] as JsonArray ?? []).OfType<JsonObject>())
            .Where(n => n["name"]?.GetValue<string>()?.StartsWith(ProbePrefix, StringComparison.Ordinal) == true)
            .Select(n => (Name: n["name"]!.GetValue<string>()[ProbePrefix.Length..], Value: Extractor.Folded(n)))
            .Where(p => p.Value is not null)
            .ToDictionary(p => p.Name, p => p.Value!);

    static JsonObject Stripped(JsonObject node)
    {
        while (node["kind"]?.GetValue<string>() is "ParenExpr" or "ImplicitCastExpr"
               && node["inner"]?.AsArray().OfType<JsonObject>().FirstOrDefault() is { } inner)
            node = inner;
        return node;
    }

    static List<string>? Members(List<JsonObject> top, string type)
    {
        var record = type.StartsWith("struct ", StringComparison.Ordinal) ? type[7..] : type;
        var typedef = top.FirstOrDefault(n => n["kind"]?.GetValue<string>() == "TypedefDecl" && n["name"]?.GetValue<string>() == record);
        if (typedef?["type"]?.AsObject()["qualType"]?.GetValue<string>() is { } target && target.StartsWith("struct ", StringComparison.Ordinal))
            record = target[7..];
        return top.LastOrDefault(n => n["kind"]?.GetValue<string>() == "RecordDecl" && n["name"]?.GetValue<string>() == record
                                      && n["completeDefinition"]?.GetValue<bool>() == true)?["inner"]?.AsArray().OfType<JsonObject>()
            .Where(f => f["kind"]?.GetValue<string>() == "FieldDecl").Select(f => f["name"]!.GetValue<string>()).ToList();
    }

    static List<string>? Literals(JsonObject compound)
    {
        var list = compound["inner"]?.AsArray().OfType<JsonObject>().FirstOrDefault(n => n["kind"]?.GetValue<string>() == "InitListExpr");
        var values = new List<string>();
        foreach (var item in list?["inner"]?.AsArray().OfType<JsonObject>() ?? [])
        {
            var literal = Stripped(item);
            while (literal["kind"]?.GetValue<string>() == "ConstantExpr" && literal["value"] is null
                   && literal["inner"]?.AsArray().OfType<JsonObject>().FirstOrDefault() is { } inner)
                literal = Stripped(inner);
            if (literal["kind"]?.GetValue<string>() is not ("IntegerLiteral" or "ConstantExpr") || literal["value"] is null) return null;
            values.Add(literal["value"]!.GetValue<string>());
        }
        return list is null ? null : values;
    }

    static bool IsInteger(string type) => type is "int" or "unsigned int" or "long" or "unsigned long" or "long long"
        or "unsigned long long" or "short" or "unsigned short" or "char" or "signed char" or "unsigned char" or "_Bool";

    [GeneratedRegex(@"^kabic_constant_(\w+) ?(.*)$", RegexOptions.Multiline)]
    private static partial Regex ExpansionLine();

    [GeneratedRegex(@"^\s*#\s*define\s+([A-Za-z_]\w*)(?![\w(])")]
    private static partial Regex ObjectLikeDefine();
}
