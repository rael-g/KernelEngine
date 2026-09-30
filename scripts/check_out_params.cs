#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(rootDir, "scripts", "api_domains.json")))!.AsObject();

var excluded = new Dictionary<string, string>
{
    ["ke_runtime_debug_compute_waves(out_wave_assignments)"] =
        "caller-allocated buffer, not a single written-back value: [out] would project "
        + "one uint where the callee fills system_count of them, and no backend renders "
        + "a writable span yet",
};

var offenders = new List<string>();

foreach (var domain in manifest["domains"]!.AsArray())
{
    var apiJson = Path.Combine(rootDir, domain!["apiJson"]!.GetValue<string>());
    if (!File.Exists(apiJson)) continue;
    var api = JsonNode.Parse(File.ReadAllText(apiJson))!.AsObject();
    var where = Path.GetRelativePath(rootDir, apiJson).Replace('\\', '/');

    foreach (var key in (string[])["vtables", "structs", "callbacks"])
        foreach (var owner in api[key]?.AsArray() ?? [])
        {
            var ownerName = owner!["name"]?.GetValue<string>() ?? "?";
            foreach (var slot in owner["slots"]?.AsArray() ?? [])
                Check(where, $"{ownerName}.{slot!["name"]}", slot["params"]);
            Check(where, ownerName, owner["params"]);
        }

    foreach (var fn in api["functions"]?.AsArray() ?? [])
        Check(where, fn!["name"]!.GetValue<string>(), fn["params"]);
}

if (offenders.Count == 0)
{
    Console.WriteLine("Every written-back parameter declares [out].");
    return 0;
}

Console.Error.WriteLine($"{offenders.Count} parameter(s) are written back but carry no [out]:");
foreach (var o in offenders.Order()) Console.Error.WriteLine($"  {o}");
Console.Error.WriteLine();
Console.Error.WriteLine("An out_-prefixed parameter without the tag reaches the managed API as a raw");
Console.Error.WriteLine("pointer the caller has to pin and dereference itself. Tag it in the header's");
Console.Error.WriteLine("doc block and regenerate, or rename the parameter if it is not written back.");
return 1;

/// <summary>
/// Records every parameter whose name says it is written back while its tags do
/// not. <c>out_error</c> is the failure lane every fallible slot carries: the
/// backends recognise it by position and name, so it is not a projected
/// parameter at all.
/// </summary>
void Check(string where, string slot, JsonNode? parameters)
{
    foreach (var p in parameters?.AsArray() ?? [])
    {
        var name = p!["name"]?.GetValue<string>();
        if (name is null or "out_error") continue;
        if (name != "out" && !name.StartsWith("out_", StringComparison.Ordinal)) continue;
        var tags = (p["tags"]?.AsArray() ?? []).Select(t => t!.GetValue<string>().Split(':')[0]);
        if (tags.Contains("out")) continue;
        if (excluded.ContainsKey($"{slot}({name})")) continue;
        offenders.Add($"{where}: {slot}({name})");
    }
}
