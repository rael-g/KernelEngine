#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Pipeline/Kabic.Pipeline.csproj

using System.Runtime.CompilerServices;
using Kabic.Pipeline;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? zigOverride = null;
string? shadowRoot = null;
var only = new List<string>();
for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--zig": zigOverride = args[++i]; break;
        case "--domain": only.Add(args[++i]); break;
        case "--into": shadowRoot = Path.GetFullPath(args[++i]); break;
    }
}

var specs = DomainSpec.Load(Path.Combine(rootDir, "scripts", "api_domains.json"))
    .Where(s => only.Count == 0 || only.Contains(s.Name))
    .ToList();

string Place(string relative) => Path.Combine(shadowRoot ?? rootDir, relative);

IReadOnlyDictionary<string, string> apis;
try
{
    apis = Regeneration.ExtractAll(specs, rootDir, zigOverride);
}
catch (InvalidOperationException e)
{
    Console.Error.WriteLine($"[!] extraction failed:\n{e.Message}");
    return 1;
}

foreach (var spec in specs)
{
    try
    {
        var output = Regeneration.Plan(spec, Place);
        Directory.CreateDirectory(Path.GetDirectoryName(output.ApiJson)!);
        File.WriteAllText(output.ApiJson, apis[spec.Name]);
        Regeneration.GenerateOne(spec, apis[spec.Name], output);
    }
    catch (InvalidOperationException e)
    {
        Console.Error.WriteLine($"[!] {spec.Name}: generation failed:\n{e.Message}");
        return 1;
    }
    Console.WriteLine($"{spec.Name}: regenerated");
}

return 0;
