#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Pipeline/Kabic.Pipeline.csproj

using Kabic.Pipeline;

string? apiPath = null, outPath = null, guard = null;
var includes = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--api": apiPath = args[++i]; break;
        case "--out": outPath = args[++i]; break;
        case "--guard": guard = args[++i]; break;
        case "--include": includes.Add(args[++i]); break;
    }
}

if (apiPath is null || outPath is null || guard is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_c.cs -- --api <ke_api.json> "
        + "--out <file.h> --guard <MACRO> [--include <header>]...");
    return 1;
}

Generation.CFieldTable(File.ReadAllText(apiPath), outPath, guard, includes);
Console.WriteLine($"wrote the field tables to {outPath}");
return 0;
