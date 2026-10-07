using System.Text.Json.Nodes;
using Kabic.C;
using Kabic.CSharp;

namespace Kabic.Pipeline;

public static class Generation
{
    public sealed record CSharpRequest(
        string ApiJson,
        string Namespace,
        string NativeNamespace,
        string OutDir,
        string ContractDir,
        string? Domain,
        string? Library,
        IReadOnlyCollection<string> Providers,
        IReadOnlyCollection<string> Callbacks,
        IReadOnlyList<string> Usings,
        Convention Convention);

    public static void CSharp(CSharpRequest r)
    {
        var model = ApiReader.Read(JsonNode.Parse(r.ApiJson)!.AsObject());
        var convention = r.Convention;
        var classified = Classifier.Classify(model, new HashSet<string>(r.Providers), new HashSet<string>(r.Callbacks), convention);
        var ns = r.Namespace;
        var nativeNs = r.NativeNamespace;
        var outDir = r.OutDir;
        var contractDir = r.ContractDir;
        var usings = r.Usings.ToList();

        Directory.CreateDirectory(outDir);

        if (model.Enums.Any(e => !e.External))
        {
            Directory.CreateDirectory(contractDir);
            var enumsFile = r.Domain is null ? "Enums.g.cs" : $"{Idioms.TypeName(r.Domain, convention)}.Enums.g.cs";
            File.WriteAllText(Path.Combine(contractDir, enumsFile), CSharpBackend.RenderEnums(model, ns, convention));
        }

        foreach (var value in model.Structs.Where(CSharpBackend.IsValue))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(value.Name, convention)}.g.cs"),
                CSharpBackend.RenderStruct(model, value, ns, usings, convention));
        }

        foreach (var borrowed in model.Structs.Where(CSharpBackend.IsBorrowed))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(borrowed.Name, convention)}.g.cs"),
                CSharpBackend.RenderBorrowed(model, borrowed, ns, usings, convention));
        }

        foreach (var view in model.Structs.Where(CSharpBackend.IsView))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(view.Name, convention)}.g.cs"),
                CSharpBackend.RenderView(model, view, ns, usings, convention));
        }

        foreach (var counted in model.Structs.Where(s => !s.External && !s.IsVtable
            && !convention.IsParamsType(s.Name)
            && !CSharpBackend.IsView(s)
            && !CSharpBackend.IsBorrowed(s)
            && s.Fields.Any(f => f.Has("array_of"))))
            File.WriteAllText(Path.Combine(outDir, $"{counted.Name}.Spans.g.cs"),
                CSharpBackend.RenderStructSpans(model, counted, nativeNs, convention));

        foreach (var kinds in model.Enums.Where(e => !e.External && e.Has("borrow_kinds")))
            File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(kinds.Name, convention)}Wrappers.g.cs"),
                CSharpBackend.RenderBorrowWrappers(kinds, ns, convention));

        foreach (var provider in classified.Providers)
        {
            var typeName = Idioms.TypeName(provider.Name, convention);
            var source = CSharpBackend.RenderProvider(model, provider, classified, ns, nativeNs, usings, convention);
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
                CSharpBackend.RenderNodeType(model, component, ns, usings, convention));
        }

        if (nodeNames.Count > 0)
        {
            if (r.Domain is null)
                throw new InvalidOperationException("domain renders node types but no domain name was given");
            var registrar = Idioms.TypeName(r.Domain, convention) + "NodeTypes";
            File.WriteAllText(Path.Combine(outDir, $"{registrar}.g.cs"),
                CSharpBackend.RenderNodeTypeRegistrar(registrar, nodeNames, ns));
        }

        foreach (var (owner, fns) in classified.FreeFunctionGroups)
        {
            if (r.Library is null)
                throw new InvalidOperationException($"domain has free functions on '{owner}' but no library was given");
            File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(owner, convention)}Functions.g.cs"),
                CSharpBackend.RenderFreeFunctions(model, owner, fns, ns, nativeNs, usings, r.Library, convention));
        }
    }

    public static void CFieldTable(string apiJson, string outPath, string guard, IReadOnlyList<string> includes, Convention convention)
    {
        var model = ApiReader.Read(JsonNode.Parse(apiJson)!.AsObject());
        var text = CBackend.RenderFieldTables(model, guard, includes.ToList(), convention);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
        File.WriteAllText(outPath, text);
    }

    public static string ErrorKinds(Convention convention)
    {
        var o = new List<string>
        {
            "// <auto-generated/>",
            "// Derived from the error kinds of api_domains.json. Do not edit.",
            "",
            $"namespace {convention.ErrorHelperNamespace};",
            "",
            $"public static unsafe partial class {convention.ErrorHelperClass}",
            "{",
            "    static bool TryCreate(string nativeName, string message, Exception? cause, out Exception exception)",
            "    {",
            "        switch (nativeName)",
            "        {",
        };
        foreach (var kind in convention.NamedErrors)
        {
            o.Add($"            case \"{kind.NativeName}\":");
            o.Add($"                exception = new {kind.Managed}(message, cause);");
            o.Add("                return true;");
        }
        o.Add("            default:");
        o.Add("                exception = null!;");
        o.Add("                return false;");
        o.Add("        }");
        o.Add("    }");
        o.Add("");
        o.Add("    static Exception CreateGeneral(string message, Exception? cause) =>");
        o.Add($"        new {convention.GeneralError.Managed}(message, cause);");
        o.Add("}");
        foreach (var kind in convention.ErrorKinds.Where(k => k.Extends is not null))
        {
            o.Add("");
            o.Add($"/// <summary>The exception for the native error <c>{kind.NativeName}</c>.</summary>");
            o.Add($"public class {kind.Managed} : {kind.Extends}");
            o.Add("{");
            o.Add($"    /// <summary>Creates the exception for a native error.</summary>");
            o.Add($"    public {kind.Managed}(string message, Exception? innerException) : base(message, innerException)");
            o.Add("    {");
            o.Add("    }");
            o.Add("}");
        }
        return string.Join('\n', o) + "\n";
    }
}
