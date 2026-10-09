using System.Text.Json.Nodes;

namespace Kabic.Pipeline;

/// <summary>
/// The C field table a domain generates: its output file, its include guard and its includes.
/// </summary>
public sealed record CFieldTableSpec(string File, string Guard, IReadOnlyList<string> Includes);

/// <summary>
/// One domain of the manifest, with its headers, its output locations and its providers.
/// </summary>
/// <remarks>
/// <c>Load</c> parses the manifest and maps each entry of its domains through <c>FromJson</c>,
/// in order. <c>FromJson</c> reads the name, the API file, the namespace, the native namespace
/// and the output directory as required keys, and reads the abstractions directory and the
/// library as optional strings. The headers, include directories, auxiliary and compose
/// headers, providers and usings are read as string lists, and an absent list is empty. A cOut
/// entry, when present, becomes a <c>CFieldTableSpec</c> with its file, guard and includes.
/// </remarks>
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
    /// <summary>
    /// Reads the manifest at the given path and returns its domains in manifest order.
    /// </summary>
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
