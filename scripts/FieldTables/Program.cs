using System.Text.Json.Nodes;
using Kabic;
using KernelEngine.FieldTables;

var check = args.Contains("--check");
var root = Directory.GetCurrentDirectory();
var manifestPath = Path.Combine(root, "scripts", "api_domains.json");
for (var i = 0; i < args.Length; i++)
{
    if (args[i] == "--root") root = Path.GetFullPath(args[++i]);
    else if (args[i] == "--manifest") manifestPath = Path.GetFullPath(args[++i]);
}

var convention = Convention.Load(manifestPath);
var domains = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject()["domains"]!.AsArray();
var stale = new List<string>();
var written = 0;

foreach (var domain in domains)
{
    if (domain!["cOut"] is not JsonObject target) continue;
    var apiJson = Path.Combine(root, domain["apiJson"]!.GetValue<string>());
    var model = ApiReader.Read(JsonNode.Parse(File.ReadAllText(apiJson))!.AsObject());
    var includes = (target["includes"]?.AsArray() ?? []).Select(n => n!.GetValue<string>()).ToList();
    var text = FieldTableBackend.RenderFieldTables(model, target["guard"]!.GetValue<string>(), includes, convention);
    var path = Path.Combine(root, target["file"]!.GetValue<string>());

    if (check)
    {
        if (!File.Exists(path) || File.ReadAllText(path) != text) stale.Add(Path.GetRelativePath(root, path).Replace('\\', '/'));
        continue;
    }

    Directory.CreateDirectory(Path.GetDirectoryName(path)!);
    File.WriteAllText(path, text);
    written++;
    Console.WriteLine($"{domain["name"]}: {Path.GetRelativePath(root, path).Replace('\\', '/')}");
}

if (!check)
{
    Console.WriteLine($"wrote {written} field table(s)");
    return 0;
}

if (stale.Count == 0)
{
    Console.WriteLine("Every component field table matches what its ke_api.json describes.");
    return 0;
}

Console.Error.WriteLine($"{stale.Count} component field table(s) differ from what their ke_api.json describes:");
foreach (var s in stale.Order()) Console.Error.WriteLine($"  {s}");
Console.Error.WriteLine("\nRun 'dotnet run --project scripts/FieldTables' and commit the result.");
return 1;
