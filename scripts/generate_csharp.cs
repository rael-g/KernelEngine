#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.CSharpBackend/Kabic.CSharpBackend.csproj

// Thin CLI shell over kabic's C# backend (src/csharp/kabic/Kabic.CSharpBackend).
// The real project is under src/csharp/ alongside every other real C# project
// in this repo (KernelEngine.Input, KernelEngine.Window, ...); this script is
// only the `dotnet run scripts/generate_csharp.cs` entry point and argument
// parsing, matching the shell/real-project split scripts/extract_api.cs and
// scripts/check_api_drift.cs will move to as they grow the same way.
//
// Frontend: scripts/extract_api.cs (headers -> ke_api.json, the IR).
// Middle-end: src/csharp/kabic/Kabic.Core (ke_api.json -> ClassifiedModel).
// Backend: src/csharp/kabic/Kabic.CSharpBackend (ClassifiedModel -> C#).
//
// Output is generated code: never hand-edit it, regenerate from ke_api.json,
// same rule that already governs src/csharp/*/Native/Generated/.
//
// Usage: dotnet run scripts/generate_csharp.cs -- --api <ke_api.json>
//        --namespace <NS> --native-namespace <NS.Native> --out <dir>
//        [--provider <vtable_name>]... [--callback <vtable_name>]...
//
// A vtable not explicitly classified via --provider/--callback is inferred:
// referenced as a [callback]-tagged parameter type anywhere => callback;
// otherwise, if it has a matching ke_X_create factory function => provider.

using System.Text.Json.Nodes;
using Kabic;
using Kabic.CSharp;

string? apiPath = null, ns = null, nativeNs = null, outDir = null, enumsOutDir = null, library = null, domain = null;
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
        case "--enums-out": enumsOutDir = args[++i]; break;
        case "--provider": explicitProviders.Add(args[++i]); break;
        case "--callback": explicitCallbacks.Add(args[++i]); break;
        // Mirrors generate_bindings.cs's .rsp `--with-using`: a factory param
        // that is a pointer into ANOTHER domain (e.g. ke_input_create's
        // `ke_logger*`) needs that domain's Native namespace in scope; nothing
        // in one domain's ke_api.json can name it, so the caller supplies it.
        case "--using": extraUsings.Add(args[++i]); break;
        // The native .so a value-type's free functions DllImport against. Not
        // derivable from ke_api.json (no plugin-to-.so mapping in the
        // description); required whenever a domain has free-function groups —
        // guessing it from the domain name is how ke_logger_simple almost
        // shipped as a DllImport against "ke_logger_default", which doesn't exist.
        case "--library": library = args[++i]; break;
        // Names the generated node-type registrar. Every domain's node types share
        // one namespace but land in different assemblies, so the class name is what
        // keeps two domains' registrars from colliding.
        case "--domain": domain = args[++i]; break;
    }
}

if (apiPath is null || ns is null || nativeNs is null || outDir is null)
{
    Console.Error.WriteLine("usage: dotnet run scripts/generate_csharp.cs -- --api <ke_api.json> "
        + "--namespace <NS> --native-namespace <NS.Native> --out <dir> "
        + "[--provider <vtable>]... [--callback <vtable>]... [--using <NS>]... [--library <so-name>] [--domain <name>]");
    return 1;
}

var api = JsonNode.Parse(File.ReadAllText(apiPath))!.AsObject();
var model = ApiReader.Read(api);
// The ABI vocabulary being compiled. Hardcoded to KernelEngine's for now; the
// eventual split (a kabic core taking a Convention, plus a thin per-project
// definition supplying one) is recorded as debt in ScriptingArchitectureV3.md.
var convention = Convention.KernelEngine;
var classified = Classifier.Classify(model, explicitProviders, explicitCallbacks, convention);

Directory.CreateDirectory(outDir);

if (model.Enums.Any(e => !e.External))
{
    var enumsDir = enumsOutDir ?? outDir;
    Directory.CreateDirectory(enumsDir);
    File.WriteAllText(Path.Combine(enumsDir, "Enums.g.cs"), CSharpBackend.RenderEnums(model, ns, convention));
}

foreach (var provider in classified.Providers)
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(provider.Name, convention)}.g.cs"),
        CSharpBackend.RenderProvider(model, provider, classified, ns, nativeNs, extraUsings, convention));

foreach (var callback in classified.Callbacks)
    File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(callback.Name, convention)}Native.g.cs"),
        CSharpBackend.RenderCallbackInterface(callback, ns, nativeNs, convention));

// A plain struct tagged [node:Name] emits a toolkit-shaped node class. Not yet wired
// per-domain like providers/enums are — every [node:]-tagged struct in this one
// ke_api.json is rendered, except the ones this domain only composes against
// (--compose): the domain that owns them already emits them, and rendering them here
// too would put a second, divergent copy of the same node type in another assembly.
var nodeNames = new List<string>();
foreach (var component in model.Structs.Where(s => !s.IsVtable && !s.External && s.Has("node")))
{
    var nodeName = component.TagValue("node")!;
    nodeNames.Add(nodeName);
    File.WriteAllText(Path.Combine(outDir, $"{nodeName}.g.cs"),
        CSharpBackend.RenderNodeType(model, component, ns, nativeNs, extraUsings, convention));
}

// The registration comes from the same header the type does. Kept by hand it
// drifts the moment a header gains a node, and the failure lands at scene-load
// time on an unresolvable type name rather than at the edit that caused it.
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
