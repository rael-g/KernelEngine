#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.ZigBackend/Kabic.ZigBackend.csproj

using System.Text.Json.Nodes;
using Kabic;
using Kabic.Zig;

string? apiPath = null, outPath = null;
var providers = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--api": apiPath = args[++i]; break;
        case "--out": outPath = args[++i]; break;
        case "--provider": providers.Add(args[++i]); break;
    }
}

if (apiPath is null || outPath is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_zig.cs -- --api <ke_api.json> "
        + "--out <file.zig> [--provider <ke_vtable>]...");
    return 1;
}

var model = ApiReader.Read(JsonNode.Parse(File.ReadAllText(apiPath))!.AsObject());
var classified = Classifier.Classify(model, providers.ToHashSet(), [], Convention.KernelEngine);
var text = ZigBackend.Render(model, classified, Convention.KernelEngine);

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
File.WriteAllText(outPath, text);

Console.WriteLine($"wrote {classified.Providers.Count} projection(s) to {outPath}");
return 0;
