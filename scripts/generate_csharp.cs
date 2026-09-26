#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.CSharpBackend/Kabic.CSharpBackend.csproj

using System.Text.Json.Nodes;
using Kabic;
using Kabic.CSharp;

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

var api = JsonNode.Parse(File.ReadAllText(apiPath))!.AsObject();
var model = ApiReader.Read(api);
var convention = Convention.KernelEngine;
var classified = Classifier.Classify(model, explicitProviders, explicitCallbacks, convention);

Directory.CreateDirectory(outDir);

var contractDir = contractOutDir ?? outDir;

if (model.Enums.Any(e => !e.External))
{
    Directory.CreateDirectory(contractDir);
    var enumsFile = domain is null
        ? "Enums.g.cs"
        : $"{Idioms.TypeName(domain, convention)}.Enums.g.cs";
    File.WriteAllText(Path.Combine(contractDir, enumsFile), CSharpBackend.RenderEnums(model, ns, convention));
}

foreach (var value in model.Structs.Where(s => s.Has("value") && !s.External && !s.IsVtable))
{
    Directory.CreateDirectory(contractDir);
    File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(value.Name, convention)}.g.cs"),
        CSharpBackend.RenderStruct(model, value, ns, convention));
}

foreach (var counted in model.Structs.Where(s => !s.External && !s.IsVtable
    && !convention.IsParamsType(s.Name)
    && s.Fields.Any(f => f.Has("array_of"))))
    File.WriteAllText(Path.Combine(outDir, $"{counted.Name}.Spans.g.cs"),
        CSharpBackend.RenderStructSpans(model, counted, nativeNs, convention));

foreach (var kinds in model.Enums.Where(e => !e.External && e.Has("borrow_kinds")))
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(kinds.Name, convention)}Wrappers.g.cs"),
        CSharpBackend.RenderBorrowWrappers(kinds, ns, convention));

foreach (var provider in classified.Providers)
{
    var typeName = Idioms.TypeName(provider.Name, convention);
    var source = CSharpBackend.RenderProvider(model, provider, classified, ns, nativeNs, extraUsings, convention);
    File.WriteAllText(Path.Combine(outDir, $"{typeName}.g.cs"), source.Class);
    if (source.Contract is not null)
    {
        Directory.CreateDirectory(contractDir);
        File.WriteAllText(Path.Combine(contractDir, $"I{typeName}.g.cs"), source.Contract);
    }
}

foreach (var callback in classified.Callbacks)
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(callback.Name, convention)}Native.g.cs"),
        CSharpBackend.RenderCallbackInterface(callback, ns, nativeNs, convention));

var nodeNames = new List<string>();
foreach (var component in model.Structs.Where(s => !s.IsVtable && !s.External && s.Has("node")))
{
    var nodeName = component.TagValue("node")!;
    nodeNames.Add(nodeName);
    File.WriteAllText(Path.Combine(outDir, $"{nodeName}.g.cs"),
        CSharpBackend.RenderNodeType(model, component, ns, nativeNs, extraUsings, convention));
}

if (nodeNames.Count > 0)
{
    if (domain is null)
    {
        Console.Error.WriteLine("error: domain renders node types but --domain was not given");
        return 1;
    }
    var registrar = Idioms.TypeName(domain, convention) + "NodeTypes";
    File.WriteAllText(Path.Combine(outDir, $"{registrar}.g.cs"),
        CSharpBackend.RenderNodeTypeRegistrar(registrar, nodeNames, ns));
}

if (classified.FreeFunctionGroups.Count > 0)
    foreach (var (owner, fns) in classified.FreeFunctionGroups)
    {
        if (library is null)
        {
            Console.Error.WriteLine($"error: domain has free functions on '{owner}' but --library was not given");
            return 1;
        }
        File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(owner, convention)}Functions.g.cs"),
            CSharpBackend.RenderFreeFunctions(model, owner, fns, ns, nativeNs, extraUsings, library, convention));
    }

Console.WriteLine($"wrote {classified.Providers.Count} provider(s), {classified.Callbacks.Count} callback(s), "
    + $"{classified.FreeFunctionGroups.Count} free-function group(s) to {outDir}");
return 0;
