using System.Text.Json.Nodes;

using Kabic.C;
using Kabic.CSharp;

namespace Kabic.Pipeline;

/// <summary>
/// Writes the C# projection, the C field tables and the error-kind mapping of an API
/// description.
/// </summary>
public static class Generation
{
    /// <summary>
    /// The inputs of one C# projection: API JSON, namespaces, directories, domain, library,
    /// providers,
    /// callbacks, usings and convention.
    /// </summary>
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

    /// <summary>
    /// Writes the C# projection of one API description into the output and contract
    /// directories. Throws <c>InvalidOperationException</c> when a node-tagged component exists
    /// and no domain is given, or when free functions exist and no library is given.
    /// </summary>
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
            File.WriteAllText(Path.Combine(contractDir, enumsFile), CSharpWriter.RenderEnums(model, ns, convention));
        }

        foreach (var value in model.Structs.Where(CSharpWriter.IsValue))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(value.Name, convention)}.g.cs"),
                CSharpWriter.RenderStruct(model, value, ns, usings, convention));
        }

        foreach (var borrowed in model.Structs.Where(CSharpWriter.IsBorrowed))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(borrowed.Name, convention)}.g.cs"),
                CSharpWriter.RenderBorrowed(model, borrowed, ns, usings, convention));
        }

        foreach (var view in model.Structs.Where(CSharpWriter.IsView))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(view.Name, convention)}.g.cs"),
                CSharpWriter.RenderView(model, view, ns, usings, convention));
        }

        foreach (var counted in model.Structs.Where(s => !s.External && !s.IsVtable
            && !convention.IsParamsType(s.Name)
            && !CSharpWriter.IsView(s)
            && !CSharpWriter.IsBorrowed(s)
            && CSharpWriter.SpannedFields(model, s, convention).Any()))
            File.WriteAllText(Path.Combine(outDir, $"{counted.Name}.Spans.g.cs"),
                CSharpWriter.RenderStructSpans(model, counted, nativeNs, convention));

        foreach (var kinds in model.Enums.Where(e => !e.External && e.Has("borrow_kinds")))
            File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(kinds.Name, convention)}Wrappers.g.cs"),
                CSharpWriter.RenderBorrowWrappers(kinds, ns, convention));

        foreach (var provider in classified.Providers)
        {
            var typeName = Idioms.TypeName(provider.Name, convention);
            var source = CSharpWriter.RenderProvider(model, provider, classified, ns, nativeNs, usings, convention);
            File.WriteAllText(Path.Combine(outDir, $"{typeName}.g.cs"), source.Class);
            if (source.Contract is not null)
            {
                Directory.CreateDirectory(contractDir);
                File.WriteAllText(Path.Combine(contractDir, $"I{typeName}.g.cs"), source.Contract);
            }
        }

        foreach (var bridged in model.Callbacks.Where(c => c.Has("bridge")))
        {
            Directory.CreateDirectory(contractDir);
            File.WriteAllText(Path.Combine(contractDir, $"{Idioms.TypeName(bridged.Name, convention)}.g.cs"),
                CSharpWriter.RenderCallbackBridge(model, bridged, ns, nativeNs, convention));
        }

        foreach (var callback in classified.Callbacks)
            File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(callback.Name, convention)}Native.g.cs"),
                CSharpWriter.RenderCallbackInterface(callback, ns, nativeNs, convention));

        var nodeNames = new List<string>();
        foreach (var component in model.Structs.Where(s => !s.IsVtable && !s.External && s.Has("node")))
        {
            var nodeName = component.TagValue("node")!;
            nodeNames.Add(nodeName);
            File.WriteAllText(Path.Combine(outDir, $"{nodeName}.g.cs"),
                CSharpWriter.RenderNodeType(model, component, ns, usings, convention));
        }

        if (nodeNames.Count > 0)
        {
            if (r.Domain is null)
                throw new InvalidOperationException("domain renders node types but no domain name was given");
            var registrar = Idioms.TypeName(r.Domain, convention) + "NodeTypes";
            File.WriteAllText(Path.Combine(outDir, $"{registrar}.g.cs"),
                CSharpWriter.RenderNodeTypeRegistrar(registrar, nodeNames, ns));
        }

        foreach (var (owner, fns) in classified.FreeFunctionGroups)
        {
            if (r.Library is null)
                throw new InvalidOperationException($"domain has free functions on '{owner}' but no library was given");
            File.WriteAllText(Path.Combine(outDir, $"{Idioms.TypeName(owner, convention)}Functions.g.cs"),
                CSharpWriter.RenderFreeFunctions(model, owner, fns, ns, nativeNs, usings, r.Library, convention));
        }
    }

    /// <summary>
    /// Renders the C field tables of an API description with the given guard and includes, and
    /// writes them to the output path.
    /// </summary>
    public static void CFieldTable(string apiJson, string outPath, string guard, IReadOnlyList<string> includes, Convention convention)
    {
        var model = ApiReader.Read(JsonNode.Parse(apiJson)!.AsObject());
        var text = CWriter.RenderFieldTables(model, guard, includes.ToList(), convention);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
        File.WriteAllText(outPath, text);
    }

    static readonly string[] ScalarKinds = ["null", "bool", "int", "float", "string"];

    static string KindMember(string kind) => char.ToUpperInvariant(kind[0]) + kind[1..];

    /// <summary>
    /// Returns the source of the managed field-table contract: <c>IComponentLayout</c>, the kinds
    /// the convention's variants name, the row and default types, and the helper that takes a row's
    /// offset and size from the struct itself.
    /// </summary>
    public static string ComponentLayout(Convention convention)
    {
        var table = convention.FieldTable!;
        var o = new List<string>
        {
            "// <auto-generated/>",
            "// Derived from the field table of api_domains.json. Do not edit.",
            "",
            "#nullable enable",
            "",
            "using System.Numerics;",
            "using System.Runtime.CompilerServices;",
            "",
            $"namespace {table.ManagedNamespace};",
            "",
            "/// <summary>",
            "/// A component whose type states its own field table: the fields a scene can address, where each",
            "/// sits in the struct, and what each holds when nothing authors it. The registry hands the table",
            "/// to the native registration, which compares it with every other registration of the same name.",
            "/// </summary>",
            "public interface IComponentLayout",
            "{",
            "    /// <summary>The table, in declaration order; empty for a component with no addressable field.</summary>",
            "    static abstract ReadOnlySpan<ComponentField> Fields { get; }",
            "}",
            "",
            $"/// <summary>How a field is addressed: one member per kind of <c>{table.EntryType}</c>.</summary>",
            "public enum ComponentFieldKind",
            "{",
        };
        foreach (var kind in table.Variants.Keys)
        {
            o.Add($"    /// <summary>Spelled <c>{table.Variants[kind].Constant}</c> natively.</summary>");
            o.Add($"    {KindMember(kind)},");
        }
        o.AddRange(
        [
            "}",
            "",
            "/// <summary>One row of a component's field table.</summary>",
            "/// <param name=\"Name\">The key a scene writes for the field.</param>",
            "/// <param name=\"Kind\">How the field is addressed.</param>",
            "/// <param name=\"Offset\">Bytes from the start of the struct.</param>",
            "/// <param name=\"Size\">Bytes the field occupies.</param>",
            "/// <param name=\"Default\">What the field holds when nothing authors it; <see cref=\"ComponentFieldValue.None\"/> leaves zero.</param>",
            "public readonly record struct ComponentField(string Name, ComponentFieldKind Kind, uint Offset, uint Size, ComponentFieldValue Default);",
            "",
            "/// <summary>",
            "/// A field's default value. <see cref=\"Kind\"/> says which member is read: <see cref=\"Bool\"/>,",
            "/// <see cref=\"Int\"/>, <see cref=\"Float\"/>, <see cref=\"Text\"/>, or the lanes of <see cref=\"Vector\"/>",
            "/// any other kind has.",
            "/// </summary>",
            "public readonly record struct ComponentFieldValue(ComponentFieldKind Kind, bool Bool, long Int, double Float, string? Text, Vector4 Vector)",
            "{",
            "    /// <summary>No default; the field stays zero.</summary>",
            "    public static ComponentFieldValue None => default;",
            "",
            "    /// <summary>A boolean default.</summary>",
            "    public static ComponentFieldValue Of(bool value) => new(ComponentFieldKind.Bool, value, 0, 0, null, default);",
            "",
            "    /// <summary>An integer default.</summary>",
            "    public static ComponentFieldValue Of(long value) => new(ComponentFieldKind.Int, false, value, 0, null, default);",
            "",
            "    /// <summary>A floating-point default.</summary>",
            "    public static ComponentFieldValue Of(double value) => new(ComponentFieldKind.Float, false, 0, value, null, default);",
            "",
            "    /// <summary>A string default.</summary>",
            "    public static ComponentFieldValue Of(string value) => new(ComponentFieldKind.String, false, 0, 0, value, default);",
            "",
            "    /// <summary>A default of any other kind, whose unused lanes are zero.</summary>",
            "    public static ComponentFieldValue Of(ComponentFieldKind kind, Vector4 value) => new(kind, false, 0, 0, null, value);",
            "}",
            "",
            "/// <summary>Builds the rows of a field table from the struct itself, so offsets and sizes are the runtime's.</summary>",
            "public static class ComponentFields",
            "{",
            "    /// <summary>",
            "    /// The row for <paramref name=\"field\"/>, which must be a field of <paramref name=\"instance\"/>:",
            "    /// its offset is the distance between the two references and its size that of",
            "    /// <typeparamref name=\"TField\"/>.",
            "    /// </summary>",
            "    public static ComponentField Row<TStruct, TField>(ref TStruct instance, ref TField field, string name,",
            "        ComponentFieldKind kind, ComponentFieldValue defaultValue)",
            "        where TStruct : unmanaged where TField : unmanaged",
            "    {",
            "        var offset = Unsafe.ByteOffset(ref Unsafe.As<TStruct, byte>(ref instance), ref Unsafe.As<TField, byte>(ref field));",
            "        return new ComponentField(name, kind, (uint)offset, (uint)Unsafe.SizeOf<TField>(), defaultValue);",
            "    }",
            "}",
        ]);
        return string.Join('\n', o) + "\n";
    }

    /// <summary>
    /// Returns the source of the conversion from a managed layout to the native entry type: a native
    /// array built once per component type and never freed, since every registry that borrows it may
    /// outlive any one caller.
    /// </summary>
    public static string NativeFieldTable(Convention convention)
    {
        var table = convention.FieldTable!;
        var o = new List<string>
        {
            "// <auto-generated/>",
            "// Derived from the field table of api_domains.json. Do not edit.",
            "",
            "using System.Numerics;",
            "using System.Runtime.CompilerServices;",
            "using System.Runtime.InteropServices;",
            $"using {table.BindingsNamespace};",
            "",
            $"namespace {table.ManagedNamespace};",
            "",
            "/// <summary>",
            $"/// The native <c>{table.EntryType}</c> array for <typeparamref name=\"T\"/>, built once from",
            "/// <see cref=\"IComponentLayout.Fields\"/> and never freed: a registry keeps the pointer for as",
            "/// long as it lives, and the table belongs to the type, not to one registry.",
            "/// </summary>",
            "internal static unsafe class NativeFieldTable<T> where T : unmanaged, IComponentLayout",
            "{",
            "    /// <summary>Rows in <see cref=\"Fields\"/>.</summary>",
            "    public static readonly int Length = T.Fields.Length;",
            "",
            "    /// <summary>The table; null when <typeparamref name=\"T\"/> describes no field.</summary>",
            $"    public static readonly {table.EntryType}* Fields = Build();",
            "",
            $"    private static {table.EntryType}* Build()",
            "    {",
            "        var rows = T.Fields;",
            "        if (rows.Length == 0) return null;",
            $"        var fields = ({table.EntryType}*)NativeMemory.AllocZeroed((nuint)rows.Length, (nuint)sizeof({table.EntryType}));",
            "        for (var i = 0; i < rows.Length; i++)",
            "        {",
            "            var row = rows[i];",
            "            fields[i].name = Utf8(row.Name);",
            "            fields[i].type = TypeOf(row.Kind);",
            "            fields[i].offset = row.Offset;",
            "            fields[i].size = row.Size;",
            "            fields[i].default_value = Value(row.Default);",
            "        }",
            "        return fields;",
            "    }",
            "",
            $"    private static {table.VariantKindType} TypeOf(ComponentFieldKind kind) => kind switch",
            "    {",
        };
        foreach (var kind in table.Variants.Keys)
            o.Add($"        ComponentFieldKind.{KindMember(kind)} => {table.VariantKindType}.{table.Variants[kind].Constant},");
        o.AddRange(
        [
            $"        _ => {table.VariantKindType}.{table.Variants["null"].Constant},",
            "    };",
            "",
            $"    private static {table.VariantType} Value(ComponentFieldValue value)",
            "    {",
            $"        {table.VariantType} v = default;",
            "        v.type = TypeOf(value.Kind);",
            "        switch (value.Kind)",
            "        {",
        ]);
        foreach (var kind in table.Variants.Keys.Where(k => k != "null"))
        {
            var member = table.Variants[kind].Member.TrimStart('.');
            var assign = kind switch
            {
                "bool" => $"v.{member} = value.Bool;",
                "int" => $"v.{member} = value.Int;",
                "float" => $"v.{member} = value.Float;",
                "string" => $"v.{member} = Utf8(value.Text ?? string.Empty);",
                _ => $"*(Vector4*)Unsafe.AsPointer(ref v.{member}) = value.Vector;",
            };
            o.Add($"            case ComponentFieldKind.{KindMember(kind)}: {assign} break;");
        }
        o.AddRange(
        [
            "        }",
            "        return v;",
            "    }",
            "",
            "    private static sbyte* Utf8(string text)",
            "    {",
            "        var bytes = System.Text.Encoding.UTF8.GetBytes(text);",
            "        var p = (byte*)NativeMemory.Alloc((nuint)bytes.Length + 1);",
            "        bytes.CopyTo(new Span<byte>(p, bytes.Length));",
            "        p[bytes.Length] = 0;",
            "        return (sbyte*)p;",
            "    }",
            "}",
        ]);
        return string.Join('\n', o) + "\n";
    }

    /// <summary>
    /// Returns the source of the mapping from each result code the convention names to its
    /// exception; a code it does not name reads as the general one.
    /// </summary>
    public static string ResultCodes(Convention convention)
    {
        var dot = convention.ResultHelperClass.LastIndexOf('.');
        var (ns, cls) = (convention.ResultHelperClass[..dot], convention.ResultHelperClass[(dot + 1)..]);
        var general = convention.ResultCodes.FirstOrDefault(r => r.Code.EndsWith("_GENERAL", StringComparison.Ordinal))
            ?? new ResultCodeSpec("", "InvalidOperationException", null);
        var o = new List<string>
        {
            "// <auto-generated/>",
            "// Derived from the result codes of api_domains.json. Do not edit.",
            "",
            "#nullable enable",
            "",
            $"namespace {ns};",
            "",
            "/// <summary>",
            "/// Turns the result code a native call returned into the exception that stands for it. The detail",
            "/// of a failure is in the failing library's log, never in the code, so the message names the call",
            "/// and the code only.",
            "/// </summary>",
            $"public static class {cls}",
            "{",
            $"    /// <summary>Throws the exception for <paramref name=\"code\"/> when it is not <c>{convention.ResultOk}</c>.</summary>",
            "    /// <param name=\"code\">What the call returned.</param>",
            "    /// <param name=\"context\">The name of the call, prefixed to the message.</param>",
            $"    public static void ThrowIfFailed({convention.ResultManagedType} code, string context)",
            "    {",
            $"        if (code != {convention.ResultManagedType}.{convention.ResultOk})",
            "            throw FromCode(code, context);",
            "    }",
            "",
            $"    /// <summary>The exception that stands for a code other than <c>{convention.ResultOk}</c>.</summary>",
            "    /// <param name=\"code\">What the call returned.</param>",
            "    /// <param name=\"context\">The name of the call, prefixed to the message.</param>",
            $"    public static Exception FromCode({convention.ResultManagedType} code, string context) =>",
            "        Create(code, $\"{context} failed with {Name(code)}; the library's log holds the detail\");",
            "",
            $"    static string Name({convention.ResultManagedType} code) =>",
            "        Enum.IsDefined(code) ? code.ToString() : $\"result code 0x{(uint)code:x8}\";",
            "",
            $"    static Exception Create({convention.ResultManagedType} code, string message) => code switch",
            "    {",
        };
        foreach (var r in convention.ResultCodes.Where(r => r != general))
            o.Add($"        {convention.ResultManagedType}.{r.Code} => new {r.Managed}(message),");
        o.Add($"        _ => new {general.Managed}(message),");
        o.Add("    };");
        o.Add("");
        o.Add("    /// <summary>");
        o.Add("    /// The code that stands for <paramref name=\"exception\"/>: the first code whose exception");
        o.Add("    /// type it is exactly, or the general code.");
        o.Add("    /// </summary>");
        o.Add("    /// <param name=\"exception\">What a managed handler threw.</param>");
        o.Add($"    public static {convention.ResultManagedType} ToCode(Exception exception) => exception.GetType().Name switch");
        o.Add("    {");
        foreach (var r in convention.ResultCodes.Where(r => r != general && r.Managed != general.Managed)
                     .GroupBy(r => r.Managed).Select(g => g.First()))
            o.Add($"        \"{r.Managed}\" => {convention.ResultManagedType}.{r.Code},");
        o.Add($"        _ => {convention.ResultManagedType}.{general.Code},");
        o.Add("    };");
        o.Add("}");
        foreach (var r in convention.ResultCodes.Where(r => r.Extends is not null))
        {
            o.Add("");
            o.Add($"/// <summary>The exception for the result code <c>{r.Code}</c>.</summary>");
            o.Add($"public class {r.Managed} : {r.Extends}");
            o.Add("{");
            o.Add("    /// <summary>Creates the exception for a result code.</summary>");
            o.Add($"    public {r.Managed}(string message) : base(message)");
            o.Add("    {");
            o.Add("    }");
            o.Add("}");
        }
        return string.Join('\n', o) + "\n";
    }
}
