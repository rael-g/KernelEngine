#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.CBackend/Kabic.CBackend.csproj

// Thin CLI shell over kabic's C backend (src/csharp/kabic/Kabic.CBackend),
// mirroring scripts/generate_csharp.cs: this file is only the entry point and
// argument parsing, the real project lives under src/csharp/ with the rest.
//
// Frontend: scripts/extract_api.cs (headers -> ke_api.json, the IR).
// Middle-end: src/csharp/kabic/Kabic.Core (ke_api.json -> ApiModel).
// Backend: src/csharp/kabic/Kabic.CBackend (ApiModel -> ke_component_field tables).
//
// Output is generated code: never hand-edit it, regenerate from ke_api.json.
//
// Usage: dotnet run scripts/generate_c.cs -- --api <ke_api.json> --out <file.h>
//        --guard <MACRO> [--include <kernel_engine/...>]...

using System.Text.Json.Nodes;
using Kabic;
using Kabic.C;

string? apiPath = null, outPath = null, guard = null;
var includes = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--api": apiPath = args[++i]; break;
        case "--out": outPath = args[++i]; break;
        case "--guard": guard = args[++i]; break;
        // The header declaring the structs the table takes offsetof against.
        // Not derivable from ke_api.json: the description records what a struct
        // is, never which file to include to get it.
        case "--include": includes.Add(args[++i]); break;
    }
}

if (apiPath is null || outPath is null || guard is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_c.cs -- --api <ke_api.json> "
        + "--out <file.h> --guard <MACRO> [--include <header>]...");
    return 1;
}

var model = ApiReader.Read(JsonNode.Parse(File.ReadAllText(apiPath))!.AsObject());
var text = CBackend.RenderFieldTables(model, guard, includes, Convention.KernelEngine);

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
File.WriteAllText(outPath, text);

Console.WriteLine($"wrote {CBackend.Describable(model, Convention.KernelEngine).Count()} field table(s) to {outPath}");
return 0;
