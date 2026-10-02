using System.Text.Json.Nodes;

namespace Kabic.Pipeline;

public sealed record CFieldTableSpec(string File, string Guard, IReadOnlyList<string> Includes);

public sealed record DomainSpec(
    string Name,
    IReadOnlyList<string> Headers,
    IReadOnlyList<string> IncludeDirs,
    IReadOnlyList<string> AuxHeaders,
    IReadOnlyList<string> ComposeHeaders,
    string ApiJson,
    string Namespace,
    string NativeNamespace,
    string OutDir,
    string? AbstractionsOutDir,
    IReadOnlyList<string> Providers,
    IReadOnlyList<string> Usings,
    string? Library,
    CFieldTableSpec? CFieldTable)
{
    public static IReadOnlyList<DomainSpec> Load(string manifestPath)
    {
        var domains = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject()["domains"]!.AsArray();
        return domains.Select(d => FromJson(d!.AsObject())).ToList();
    }

    static DomainSpec FromJson(JsonObject d)
    {
        static List<string> Strings(JsonNode? node) =>
            node?.AsArray().Select(n => n!.GetValue<string>()).ToList() ?? [];

        var cOut = d["cOut"] as JsonObject;
        return new DomainSpec(
            d["name"]!.GetValue<string>(),
            Strings(d["headers"]),
            Strings(d["includeDirs"]),
            Strings(d["auxHeaders"]),
            Strings(d["composeHeaders"]),
            d["apiJson"]!.GetValue<string>(),
            d["namespace"]!.GetValue<string>(),
            d["nativeNamespace"]!.GetValue<string>(),
            d["outDir"]!.GetValue<string>(),
            d["abstractionsOutDir"]?.GetValue<string>(),
            Strings(d["providers"]),
            Strings(d["usings"]),
            d["library"]?.GetValue<string>(),
            cOut is null ? null : new CFieldTableSpec(
                cOut["file"]!.GetValue<string>(), cOut["guard"]!.GetValue<string>(), Strings(cOut["includes"])));
    }
}
