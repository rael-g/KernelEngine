using System.Collections.Generic;
using System.Collections.Immutable;
using System.Linq;
using System.Text;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace KernelEngine.Framework.Nodes.Generator;

/// <summary>
/// Completes every partial class marked <c>[NodeType]</c>: its partial properties become the fields of
/// its nodes, laid out in one struct the node type registers, the exported ones in its field table;
/// the value the constructor gives them is the value a node is born with; <c>Ready</c>, <c>Update</c>,
/// <c>FixedUpdate</c> and every <c>[On&lt;T&gt;]</c> method become its behaviours. Everything it writes is a
/// call to the node types' API.
/// </summary>
[Generator]
public sealed class NodeTypeGenerator : IIncrementalGenerator
{
    const string Attribute = "KernelEngine.Framework.Nodes.NodeTypeAttribute";

    static readonly DiagnosticDescriptor NotPartial = new("KENG001", "A node type is partial",
        "Node type {0} is not partial", "KernelEngine.Nodes", DiagnosticSeverity.Error, true);

    static readonly DiagnosticDescriptor StateField = new("KENG002", "A node type keeps no state in a field",
        "Field {0} of node type {1} is shared by every node of the type; make it a partial property, or readonly when it is a dependency",
        "KernelEngine.Nodes", DiagnosticSeverity.Error, true);

    static readonly DiagnosticDescriptor NoLength = new("KENG004", "A text property states its length",
        "Text property {0} of node type {1} needs [MaxLength(n)]: a node holds its text in n bytes",
        "KernelEngine.Nodes", DiagnosticSeverity.Error, true);

    static readonly DiagnosticDescriptor NoTable = new("KENG003", "An exported property has a field table type",
        "Property {0} of node type {1} is a {2}, which a scene cannot write; export a number, a bool, a vector, an ActionRef or an inline array of bytes",
        "KernelEngine.Nodes", DiagnosticSeverity.Error, true);

    /// <inheritdoc/>
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        context.RegisterPostInitializationOutput(static ctx => ctx.AddSource("NodeAttributes.g.cs", Attributes));
        var types = context.SyntaxProvider.ForAttributeWithMetadataName(Attribute,
            static (node, _) => node is ClassDeclarationSyntax,
            static (ctx, _) => (Symbol: (INamedTypeSymbol)ctx.TargetSymbol, Syntax: (ClassDeclarationSyntax)ctx.TargetNode,
                Name: (string)ctx.Attributes[0].ConstructorArguments[0].Value!));
        context.RegisterSourceOutput(types, static (spc, t) => Emit(spc, t.Symbol, t.Syntax, t.Name));
    }

    static void Emit(SourceProductionContext spc, INamedTypeSymbol type, ClassDeclarationSyntax syntax, string name)
    {
        if (!syntax.Modifiers.Any(m => m.ValueText == "partial"))
        {
            spc.ReportDiagnostic(Diagnostic.Create(NotPartial, syntax.Identifier.GetLocation(), type.Name));
            return;
        }
        foreach (var field in type.GetMembers().OfType<IFieldSymbol>())
            if (!field.IsStatic && !field.IsConst && !field.IsReadOnly && !field.IsImplicitlyDeclared && field.AssociatedSymbol is null)
                spc.ReportDiagnostic(Diagnostic.Create(StateField, field.Locations.FirstOrDefault(), field.Name, type.Name));

        var properties = type.GetMembers().OfType<IPropertySymbol>().Where(p => p.IsPartialDefinition && !p.IsStatic).ToList();
        var fields = new List<(IPropertySymbol Property, string? Variant, string Size)>();
        var texts = new Dictionary<IPropertySymbol, int>(SymbolEqualityComparer.Default);
        foreach (var p in properties)
        {
            var exported = p.GetAttributes().Any(a => a.AttributeClass?.ToDisplayString() == "KernelEngine.Framework.Nodes.ExportAttribute");
            if (p.Type.SpecialType == SpecialType.System_String)
            {
                var max = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.ToDisplayString() == "System.ComponentModel.DataAnnotations.MaxLengthAttribute");
                if (max is null || max.ConstructorArguments.Length != 1 || max.ConstructorArguments[0].Value is not int length)
                {
                    spc.ReportDiagnostic(Diagnostic.Create(NoLength, p.Locations.FirstOrDefault(), p.Name, type.Name));
                    return;
                }
                texts[p] = length;
                fields.Add((p, exported ? "String" : null, length.ToString()));
                continue;
            }
            var table = exported ? Table(p.Type) : null;
            if (exported && table is null)
            {
                spc.ReportDiagnostic(Diagnostic.Create(NoTable, p.Locations.FirstOrDefault(), p.Name, type.Name, p.Type.ToDisplayString()));
                return;
            }
            fields.Add((p, table?.Variant, table?.Size ?? ""));
        }

        var methods = type.GetMembers().OfType<IMethodSymbol>().Where(m => !m.IsStatic).ToList();
        bool Has(string method) => methods.Any(m => m.Name == method && m.Parameters.Length == 0);
        var handlers = methods.Select(m => (Method: m, Event: m.GetAttributes()
                .FirstOrDefault(a => a.AttributeClass is { IsGenericType: true } c && c.ConstructedFrom.ToDisplayString() == "KernelEngine.Framework.Nodes.OnAttribute<T>")
                ?.AttributeClass!.TypeArguments[0]))
            .Where(h => h.Event is not null).ToList();

        var o = new StringBuilder();
        o.Append("// <auto-generated/>\n#nullable enable\n\n");
        if (!type.ContainingNamespace.IsGlobalNamespace) o.Append($"namespace {type.ContainingNamespace.ToDisplayString()};\n\n");
        o.Append($"partial class {type.Name}\n{{\n");
        o.Append("    /// <summary>The fields every node of the type holds, as its node type registers them.</summary>\n");
        o.Append("    [global::System.Runtime.InteropServices.StructLayout(global::System.Runtime.InteropServices.LayoutKind.Sequential)]\n");
        o.Append("    public struct NodeFields\n    {\n");
        foreach (var f in fields)
            o.Append(texts.TryGetValue(f.Property, out var bytes)
                ? $"        public Text{bytes} {f.Property.Name};\n"
                : $"        public {f.Property.Type.ToDisplayString()} {f.Property.Name};\n");
        o.Append("    }\n\n");
        foreach (var length in texts.Values.Distinct())
        {
            o.Append($"    /// <summary>{length} bytes of UTF-8 text, NUL-terminated.</summary>\n");
            o.Append($"    [global::System.Runtime.CompilerServices.InlineArray({length})]\n");
            o.Append($"    public struct Text{length}\n    {{\n        byte _first;\n    }}\n\n");
        }
        if (texts.Count > 0)
        {
            o.Append("    static string ReadText(global::System.ReadOnlySpan<byte> bytes)\n    {\n");
            o.Append("        var end = global::System.MemoryExtensions.IndexOf(bytes, (byte)0);\n");
            o.Append("        return global::System.Text.Encoding.UTF8.GetString(end < 0 ? bytes : bytes.Slice(0, end));\n    }\n\n");
            o.Append("    static void WriteText(global::System.Span<byte> bytes, string? text)\n    {\n");
            o.Append("        bytes.Clear();\n");
            o.Append("        var encoded = global::System.Text.Encoding.UTF8.GetBytes(text ?? \"\");\n");
            o.Append("        global::System.MemoryExtensions.AsSpan(encoded, 0, global::System.Math.Min(encoded.Length, bytes.Length - 1)).CopyTo(bytes);\n    }\n\n");
        }
        o.Append("    NodeFields _born;\n\n");
        o.Append("    ref NodeFields Fields => ref Bound ? ref Ctx.Fields<NodeFields>() : ref _born;\n\n");
        o.Append("    struct NodeProbe\n    {\n        public byte Head;\n        public NodeFields Value;\n    }\n\n");
        o.Append("    static int AlignOf()\n    {\n        var probe = new NodeProbe { Head = 1 };\n");
        o.Append("        return (int)global::System.Runtime.CompilerServices.Unsafe.ByteOffset(ref probe.Head, ref global::System.Runtime.CompilerServices.Unsafe.As<NodeFields, byte>(ref probe.Value));\n    }\n\n");
        o.Append("    static uint Offset<TField>(ref NodeFields value, ref TField field) =>\n");
        o.Append("        (uint)global::System.Runtime.CompilerServices.Unsafe.ByteOffset(ref global::System.Runtime.CompilerServices.Unsafe.As<NodeFields, byte>(ref value), ref global::System.Runtime.CompilerServices.Unsafe.As<TField, byte>(ref field));\n\n");
        foreach (var f in fields)
        {
            var declared = f.Property.DeclaringSyntaxReferences.Select(r => r.GetSyntax()).OfType<PropertyDeclarationSyntax>().First();
            var access = string.Join(" ", declared.Modifiers.Select(m => m.ValueText).Where(m => m != "partial"));
            var body = texts.ContainsKey(f.Property)
                ? $"get => ReadText(Fields.{f.Property.Name}); set => WriteText(Fields.{f.Property.Name}, value);"
                : $"get => Fields.{f.Property.Name}; set => Fields.{f.Property.Name} = value;";
            o.Append($"    {access}{(access.Length > 0 ? " " : "")}partial {f.Property.Type.ToDisplayString()} {f.Property.Name} {{ {body} }}\n\n");
        }

        o.Append("    /// <inheritdoc/>\n");
        o.Append("    protected override global::KernelEngine.Ecs.ComponentId RegisterInto(global::KernelEngine.Framework.Nodes.NodeWorld world)\n    {\n");
        if (Has("Born")) o.Append("        Born();\n");
        if (fields.Any(f => f.Variant is not null)) o.Append("        var probe = new NodeFields();\n");
        o.Append("        global::KernelEngine.Ecs.ComponentField[] table =\n        [\n");
        foreach (var f in fields.Where(f => f.Variant is not null))
            o.Append($"            new() {{ Name = \"{Snake(f.Property.Name)}\", Type = global::KernelEngine.Ecs.VariantType.{f.Variant}, Offset = Offset(ref probe, ref probe.{f.Property.Name}), Size = {f.Size} }},\n");
        o.Append("        ];\n");
        var sized = fields.Count > 0;
        var args = new List<string>
        {
            $"\"{name}\"",
            sized ? "fieldsSize: (nuint)global::System.Runtime.CompilerServices.Unsafe.SizeOf<NodeFields>()" : "fieldsSize: 0",
            sized ? "fieldsAlignment: (nuint)AlignOf()" : "fieldsAlignment: 0",
            "fields: table",
        };
        if (sized) args.Add("initial: global::System.Runtime.InteropServices.MemoryMarshal.AsBytes(new[] { _born }.AsSpan()).ToArray()");
        args.Add("with: [.. With]");
        if (Has("Ready")) args.Add("ready: ctx => Visit(ctx, Ready)");
        if (Has("Update")) args.Add("update: ctx => Visit(ctx, Update)");
        if (Has("FixedUpdate")) args.Add("fixedUpdate: ctx => Visit(ctx, FixedUpdate)");
        if (handlers.Count > 0)
        {
            args.Add($"events: [{string.Join(", ", handlers.Select(h => $"world.EventId<{h.Event!.ToDisplayString()}>()"))}]");
            var dispatch = string.Join(" ", handlers.Select(h =>
                $"if (Ctx.EventType == World.EventId<{h.Event!.ToDisplayString()}>()) {h.Method.Name}(Ctx.Event<{h.Event.ToDisplayString()}>());"));
            args.Add($"on: ctx => Visit(ctx, () => {{ {dispatch} }})");
        }
        o.Append($"        return world.Types.RegisterType({string.Join(", ", args)});\n");
        o.Append("    }\n}\n");
        spc.AddSource($"{type.ToDisplayString().Replace('<', '_').Replace('>', '_')}.NodeType.g.cs", o.ToString());
    }

    const string Attributes = "// <auto-generated/>\n" + """
        #nullable enable

        namespace KernelEngine.Framework.Nodes
        {
            /// <summary>Makes a partial class deriving from <c>Node</c> a node type registered under <see cref="Name"/>.</summary>
            [global::System.AttributeUsage(global::System.AttributeTargets.Class, Inherited = false)]
            internal sealed class NodeTypeAttribute(string name) : global::System.Attribute
            {
                /// <summary>The name the type is registered under and a scene names it by.</summary>
                public string Name { get; } = name;
            }

            /// <summary>Puts a partial property of a node type in its field table, so a scene can write it.</summary>
            [global::System.AttributeUsage(global::System.AttributeTargets.Property, Inherited = false)]
            internal sealed class ExportAttribute : global::System.Attribute;

            /// <summary>Makes a method of a node type the handler of the events of type <typeparamref name="T"/>.</summary>
            [global::System.AttributeUsage(global::System.AttributeTargets.Method, Inherited = false)]
            internal sealed class OnAttribute<T> : global::System.Attribute where T : unmanaged;
        }
        """;

    static (string Variant, string Size)? Table(ITypeSymbol type)
    {
        switch (type.SpecialType)
        {
            case SpecialType.System_Single: return ("Float", "4");
            case SpecialType.System_Int32:
            case SpecialType.System_UInt32: return ("Int", "4");
            case SpecialType.System_Boolean: return ("Bool", "1");
        }
        switch (type.ToDisplayString())
        {
            case "System.Numerics.Vector2": return ("Vec2", "8");
            case "System.Numerics.Vector3": return ("Vec3", "12");
            case "System.Numerics.Vector4": return ("Vec4", "16");
            case "System.Numerics.Quaternion": return ("Quat", "16");
            case "KernelEngine.Framework.Nodes.Native.ActionRef": return ("String", "32");
        }
        var inline = type.GetAttributes().FirstOrDefault(a => a.AttributeClass?.ToDisplayString() == "System.Runtime.CompilerServices.InlineArrayAttribute");
        var element = type.GetMembers().OfType<IFieldSymbol>().FirstOrDefault(f => !f.IsStatic)?.Type.SpecialType;
        if (inline is not null && inline.ConstructorArguments.Length == 1 && inline.ConstructorArguments[0].Value is int length && element == SpecialType.System_Byte)
            return ("String", length.ToString());
        return null;
    }

    static string Snake(string name)
    {
        var o = new StringBuilder();
        for (var i = 0; i < name.Length; i++)
        {
            if (char.IsUpper(name[i]) && i > 0 && (char.IsLower(name[i - 1]) || char.IsDigit(name[i - 1]))) o.Append('_');
            o.Append(char.ToLowerInvariant(name[i]));
        }
        return o.ToString();
    }
}
