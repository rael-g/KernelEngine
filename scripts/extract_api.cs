#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Pipeline/Kabic.Pipeline.csproj

using Kabic.Pipeline;

string? outPath = null;
string? zigOverride = null;
var includeDirs = new List<string>();
var headers = new List<string>();
var auxHeaders = new List<string>();
var composeHeaders = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--out": outPath = args[++i]; break;
        case "--zig": zigOverride = args[++i]; break;
        case "-I": includeDirs.Add(args[++i]); break;
        case "--aux": auxHeaders.Add(args[++i]); break;
        case "--compose": composeHeaders.Add(args[++i]); break;
        default: headers.Add(args[i]); break;
    }
}

if (outPath is null || headers.Count == 0)
{
    Console.Error.WriteLine("usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... "
        + "[--aux <header.h>]... [--compose <header.h>]... <header.h>...");
    return 1;
}

string json;
try
{
    json = Extraction.Run(new Extraction.Request(headers, includeDirs, auxHeaders, composeHeaders, zigOverride));
}
catch (InvalidOperationException e)
{
    Console.Error.WriteLine(e.Message);
    return 1;
}

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
File.WriteAllText(outPath, json);
Console.WriteLine($"wrote {outPath}");
return 0;
