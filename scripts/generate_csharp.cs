#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Pipeline/Kabic.Pipeline.csproj

using Kabic.Pipeline;

string? apiPath = null, ns = null, nativeNs = null, outDir = null, contractOutDir = null, library = null, domain = null;
var explicitProviders = new HashSet<string>();
var explicitCallbacks = new HashSet<string>();
var extraUsings = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--api": apiPath = args[++i]; break;
        case "--namespace": ns = args[++i]; break;
        case "--native-namespace": nativeNs = args[++i]; break;
        case "--out": outDir = args[++i]; break;
        case "--contract-out": contractOutDir = args[++i]; break;
        case "--provider": explicitProviders.Add(args[++i]); break;
        case "--callback": explicitCallbacks.Add(args[++i]); break;
        case "--using": extraUsings.Add(args[++i]); break;
        case "--library": library = args[++i]; break;
        case "--domain": domain = args[++i]; break;
    }
}

if (apiPath is null || ns is null || nativeNs is null || outDir is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_csharp.cs -- --api <ke_api.json> "
        + "--namespace <NS> --native-namespace <NS.Native> --out <dir> "
        + "[--contract-out <dir>] [--provider <vtable>]... [--callback <vtable>]... [--using <NS>]..."
        + " [--library <so-name>] [--domain <name>]");
    return 1;
}

try
{
    Generation.CSharp(new Generation.CSharpRequest(File.ReadAllText(apiPath), ns, nativeNs, outDir,
        contractOutDir ?? outDir, domain, library, explicitProviders, explicitCallbacks, extraUsings));
}
catch (InvalidOperationException e)
{
    Console.Error.WriteLine($"error: {e.Message}");
    return 1;
}

Console.WriteLine($"wrote the C# projection to {outDir}");
return 0;
