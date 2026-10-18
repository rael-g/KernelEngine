using System;
using System.Collections.Immutable;
using System.Linq;
using System.Text;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace KernelEngine.SourceGenerators;

/// <summary>
/// Source generator that completes a node class deriving from <c>Node</c>: the component slots
/// behind its <c>partial</c> properties, the dispatch of its <c>Update</c> and <c>On</c>
/// methods, and the registration of its component for scene files.
/// </summary>
[Generator]
public sealed class NodePropertyGenerator : IIncrementalGenerator
{
    /// <summary>
    /// Registers the classes that have a <c>partial</c> auto-property or a method named
    /// <c>Update</c>, <c>FixedUpdate</c> or <c>On</c> with at least one parameter, and generates one part for each
    /// that derives from <c>Node</c>.
    /// </summary>
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var propertyOwners = context.SyntaxProvider.CreateSyntaxProvider(
            static (node, _) => node is PropertyDeclarationSyntax { Parent: ClassDeclarationSyntax } p && IsPartialAutoProperty(p),
            static (ctx, _) => (ClassDeclarationSyntax)ctx.Node.Parent!);

        var behaviorOwners = context.SyntaxProvider.CreateSyntaxProvider(
            static (node, _) => node is MethodDeclarationSyntax { Parent: ClassDeclarationSyntax c } m
                && (m.Identifier.ValueText == "Update" || m.Identifier.ValueText == "FixedUpdate" || m.Identifier.ValueText == "On")
                && m.ParameterList.Parameters.Count > 0
                && c is not null,
            static (ctx, _) => (ClassDeclarationSyntax)ctx.Node.Parent!);

        var classes = propertyOwners.Collect()
            .Combine(behaviorOwners.Collect())
            .SelectMany(static (pair, _) => pair.Left.Concat(pair.Right).Distinct());

        context.RegisterSourceOutput(classes.Combine(context.CompilationProvider),
            static (spc, pair) => Generate(spc, pair.Left, pair.Right));
    }

    static bool IsPartialAutoProperty(PropertyDeclarationSyntax p)
    {
        if (!p.Modifiers.Any(SyntaxKind.PartialKeyword)) return false;
        if (p.AccessorList is null) return false;
        foreach (var a in p.AccessorList.Accessors)
            if (a.Body is not null || a.ExpressionBody is not null) return false;
        return true;
    }

    /// <summary>
    /// Emits <c>&lt;Class&gt;.NodeProperties.g.cs</c>, one <c>partial</c> part with a slot per
    /// component the class owns: a state field, a component id and a ref accessor. The slots come
    /// from every <c>GeneratedNodeComponent</c> attribute on the class's own declaration, or, with
    /// none, from one slot backed by a struct written from the <c>partial</c> properties and
    /// named after the class in snake case. A property goes to the slot whose struct declares its
    /// field. Behavior members are emitted for each hook the class declares, <c>Update</c> or
    /// <c>FixedUpdate</c>, or whose <c>Node</c> override it writes. A class that is not
    /// <c>partial</c> emits nothing, and reports <c>KESG005</c> for each hook it declares.
    /// Property and field types must match, or differ only by <c>bool</c> over <c>byte</c>, or
    /// <c>string</c> over a character array;
    /// otherwise <c>KESG001</c>. A property that no slot, or more than one slot, declares is
    /// <c>KESG002</c>, and <c>KESG003</c> is a pin naming a struct the class does not carry.
    /// </summary>
    static void Generate(SourceProductionContext spc, ClassDeclarationSyntax classDecl, Compilation compilation)
    {
        var model = compilation.GetSemanticModel(classDecl.SyntaxTree);
        if (model.GetDeclaredSymbol(classDecl) is not INamedTypeSymbol classSymbol) return;
        if (!DerivesFromNode(classSymbol)) return;

        if (!classDecl.Modifiers.Any(SyntaxKind.PartialKeyword))
        {
            foreach (var hook in Hooks)
                if (classSymbol.GetMembers(hook.Method).OfType<IMethodSymbol>().Any(m =>
                        SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol) && m.Parameters.Length > 0))
                    spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, classDecl.Identifier.GetLocation(),
                        classSymbol.Name, hook.Method, "the class is not partial"));
            return;
        }

        var properties = classSymbol.GetMembers().OfType<IPropertySymbol>()
            .Where(p => p.DeclaringSyntaxReferences.Any(r => r.GetSyntax() is PropertyDeclarationSyntax pd && IsPartialAutoProperty(pd)))
            .ToImmutableArray();

        var markers = classSymbol.GetAttributes()
            .Where(a => a.AttributeClass?.Name == "GeneratedNodeComponentAttribute")
            .ToImmutableArray();

        var ns = classSymbol.ContainingNamespace.IsGlobalNamespace ? null : classSymbol.ContainingNamespace.ToDisplayString();
        var className = classSymbol.Name;

        INamedTypeSymbol? nodeType = classSymbol.BaseType;
        while (nodeType is not null && nodeType.Name != "Node") nodeType = nodeType.BaseType;
        var overrideModifier = nodeType is not null && SymbolEqualityComparer.Default.Equals(nodeType.ContainingAssembly, classSymbol.ContainingAssembly)
            ? "protected internal"
            : "protected";

        var isNative = markers.Length > 0;
        var slots = isNative
            ? markers.Select((m, i) => new Slot(
                    (INamedTypeSymbol)m.ConstructorArguments[0].Value!,
                    ((INamedTypeSymbol)m.ConstructorArguments[0].Value!).ToDisplayString(),
                    (string)m.ConstructorArguments[1].Value!,
                    i))
                .ToImmutableArray()
            : properties.IsEmpty
                ? ImmutableArray<Slot>.Empty
                : [new Slot(null, "Data", SnakeCase(className), 0)];

        var sb = new StringBuilder();
        sb.AppendLine("// <auto-generated/>");
        if (ns is not null) sb.AppendLine($"namespace {ns};").AppendLine();

        sb.AppendLine($"public partial class {className}");
        sb.AppendLine("{");

        if (!isNative && !slots.IsEmpty)
        {
            sb.AppendLine("    private static readonly string GeneratedComponentName =");
            sb.AppendLine($"        global::KernelEngine.Framework.NodeTypeRegistry.Normalize(typeof({className}).FullName!);");
            sb.AppendLine("    private static readonly string GeneratedComponentAlias =");
            sb.AppendLine($"        global::KernelEngine.Framework.NodeTypeRegistry.Normalize(typeof({className}).Name);");
            sb.AppendLine();
            foreach (var p in properties.Where(p => p.Type.SpecialType == SpecialType.System_String))
            {
                sb.AppendLine($"    [global::System.Runtime.CompilerServices.InlineArray({TextCapacityOf(p)})]");
                sb.AppendLine($"    private struct {p.Name}Buffer {{ private byte _first; }}");
                sb.AppendLine();
            }

            sb.AppendLine($"    private struct {slots[0].TypeName} : global::KernelEngine.Ecs.IComponentLayout");
            sb.AppendLine("    {");
            foreach (var p in properties)
                sb.AppendLine(p.Type.SpecialType == SpecialType.System_String
                    ? $"        public {p.Name}Buffer {p.Name};"
                    : $"        public {p.Type.ToDisplayString()} {p.Name};");
            EmitLayout(sb, slots[0].TypeName, properties);
            sb.AppendLine("    }");
            sb.AppendLine();
        }

        foreach (var slot in slots)
        {
            sb.AppendLine(HasDefault(slot.Symbol)
                ? $"    private {slot.TypeName} {slot.State} = {slot.TypeName}.Default;"
                : $"    private {slot.TypeName} {slot.State};");
            sb.AppendLine($"    private uint {slot.Cid};");
        }
        sb.AppendLine();

        var borrowList = new List<IParameterSymbol>();
        var anyHook = false;
        var anyHandWritten = false;
        var precise = new List<(Hook Hook, List<BehaviorAccess.Use> Uses, ImmutableArray<IParameterSymbol> Borrows)>();
        foreach (var hook in Hooks)
        {
            var hookBorrows = EmitHook(spc, sb, classSymbol, overrideModifier, hook, out var declared, out var handWritten);
            anyHook |= declared;
            anyHandWritten |= handWritten;
            borrowList.AddRange(hookBorrows);
            if (!declared) continue;
            if (handWritten)
            {
                var written = classSymbol.GetMembers(hook.Override).OfType<IMethodSymbol>().First(m =>
                    SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol) && m.IsOverride);
                spc.ReportDiagnostic(Diagnostic.Create(WholeTypeAccessRule, written.Locations.FirstOrDefault(),
                    classSymbol.Name, hook.Override, $"it overrides {hook.Override} by hand instead of declaring {hook.Method}"));
                continue;
            }
            var method = classSymbol.GetMembers(hook.Method).OfType<IMethodSymbol>().FirstOrDefault(m =>
                SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol)
                && m.Parameters.Length > 0 && m.Parameters[0].Type.Name == "View");
            if (method is null) continue;
            if (BehaviorAccess.Analyze(compilation, classSymbol, method, out var unknown) is { } uses)
                precise.Add((hook, uses, hookBorrows));
            else if (unknown!.Foreign)
                spc.ReportDiagnostic(Diagnostic.Create(ForeignNodeRule, unknown.Location,
                    classSymbol.Name, hook.Method, unknown.Reason));
            else
                spc.ReportDiagnostic(Diagnostic.Create(WholeTypeAccessRule, unknown.Location,
                    classSymbol.Name, hook.Method, unknown.Reason));
        }
        if (precise.Count > 0) EmitHookComponents(sb, className, overrideModifier, precise);
        var borrows = borrowList.ToImmutableArray();

        if (anyHook)
        {
            var reachesOnlySelf = !anyHandWritten && borrows.Length == 0;
            sb.AppendLine($"    {overrideModifier} override bool ReachesOnlyItself => {(reachesOnlySelf ? "true" : "false")};");
            sb.AppendLine();
        }

        var writtenSlots = new HashSet<string>();

        var signalTypes = SignalTypesOf(classSymbol, borrows);

        var needsUtf8Helpers = false;

        foreach (var p in properties)
        {
            var fieldAttr = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NativeFieldAttribute");
            var declaredFieldName = fieldAttr is not null ? (string)fieldAttr.ConstructorArguments[0].Value! : p.Name;
            var pinned = NamedComponentOf(fieldAttr);

            var slot = ResolveSlot(spc, p, slots, isNative, declaredFieldName, pinned);
            if (slot is null) continue;

            var writes = p.SetMethod is not null;
            if (writes) writtenSlots.Add(slot.ComponentName);

            var backingTypeSymbol = slot.Symbol;

            var fieldName = isNative ? declaredFieldName : p.Name;
            var fieldSymbol = backingTypeSymbol?.GetMembers(fieldName).OfType<IFieldSymbol>().FirstOrDefault();
            if (p.Type.SpecialType == SpecialType.System_String && !isNative)
            {
                needsUtf8Helpers = true;
                sb.AppendLine($"    public partial string {p.Name}");
                sb.AppendLine("    {");
                sb.AppendLine("        get");
                sb.AppendLine("        {");
                sb.AppendLine($"            ref var s = ref {slot.Current}(out _);");
                sb.AppendLine($"            return GeneratedUtf8Get(ref s.{p.Name});");
                sb.AppendLine("        }");
                if (writes)
                {
                    sb.AppendLine("        set");
                    sb.AppendLine("        {");
                    sb.AppendLine($"            ref var s = ref {slot.Current}(out var live);");
                    sb.AppendLine($"            GeneratedUtf8Set(ref s.{p.Name}, value, \"{p.Name}\");");
                    sb.AppendLine($"            if (!live && IsBound) GeneratedSet({slot.Cid}, s);");
                    sb.AppendLine("        }");
                }
                sb.AppendLine("    }");
                continue;
            }

            if (p.Type.SpecialType == SpecialType.System_String && fieldSymbol is not null
                && fieldSymbol.Type.SpecialType != SpecialType.System_String)
            {
                needsUtf8Helpers = true;
                sb.AppendLine($"    public partial string {p.Name}");
                sb.AppendLine("    {");
                sb.AppendLine("        get");
                sb.AppendLine("        {");
                sb.AppendLine($"            ref var s = ref {slot.Current}(out _);");
                sb.AppendLine($"            return GeneratedUtf8Get(ref s.{fieldName});");
                sb.AppendLine("        }");
                if (writes)
                {
                    sb.AppendLine("        set");
                    sb.AppendLine("        {");
                    sb.AppendLine($"            ref var s = ref {slot.Current}(out var live);");
                    sb.AppendLine($"            GeneratedUtf8Set(ref s.{fieldName}, value, \"{p.Name}\");");
                    sb.AppendLine($"            if (!live && IsBound) GeneratedSet({slot.Cid}, s);");
                    sb.AppendLine("        }");
                }
                sb.AppendLine("    }");
                continue;
            }

            var coercion = fieldSymbol is not null ? CoercionFor(p.Type, fieldSymbol.Type) : null;

            if (fieldSymbol is not null && coercion is null
                && !SymbolEqualityComparer.Default.Equals(p.Type, fieldSymbol.Type))
            {
                spc.ReportDiagnostic(Diagnostic.Create(NoCoercionRule, p.Locations.FirstOrDefault(),
                    p.Name, p.Type.ToDisplayString(), fieldSymbol.Type.ToDisplayString()));
                continue;
            }

            sb.AppendLine($"    public partial {p.Type.ToDisplayString()} {p.Name}");
            sb.AppendLine("    {");
            sb.AppendLine("        get");
            sb.AppendLine("        {");
            sb.AppendLine($"            ref var s = ref {slot.Current}(out _);");
            sb.AppendLine(coercion is not null
                ? $"            return {coercion.Value.read("s." + fieldName)};"
                : $"            return s.{fieldName};");
            sb.AppendLine("        }");
            if (writes)
            {
                sb.AppendLine("        set");
                sb.AppendLine("        {");
                sb.AppendLine($"            ref var s = ref {slot.Current}(out var live);");
                if (coercion is not null)
                    sb.AppendLine($"            s.{fieldName} = {coercion.Value.write("value")};");
                else
                    sb.AppendLine($"            s.{fieldName} = value;");
                sb.AppendLine($"            if (!live && IsBound) GeneratedSet({slot.Cid}, s);");
                sb.AppendLine("        }");
            }
            sb.AppendLine("    }");
        }

        sb.AppendLine();
        sb.AppendLine($"    {overrideModifier} override void CollectBehaviorComponents(global::System.Collections.Generic.List<global::KernelEngine.Framework.NodeComponentUse> into)");
        sb.AppendLine("    {");
        sb.AppendLine("        base.CollectBehaviorComponents(into);");
        foreach (var slot in slots)
            sb.AppendLine($"        into.Add(new({slot.NameExpression}, {(writtenSlots.Contains(slot.ComponentName) ? "true" : "false")}, true));");
        foreach (var b in borrows)
        {
            if (BorrowKindOf(b.Type) == "Emit") continue;
            foreach (var cn in BehaviorAccess.AllComponentsOf((INamedTypeSymbol)((INamedTypeSymbol)b.Type).TypeArguments[0]))
                sb.AppendLine($"        into.Add(new({cn}, true, false));");
        }
        sb.AppendLine("    }");
        sb.AppendLine();

        if (needsUtf8Helpers)
        {
            sb.AppendLine();
            sb.AppendLine("    private static string GeneratedUtf8Get<TBuf>(ref TBuf buffer) where TBuf : struct");
            sb.AppendLine("    {");
            sb.AppendLine("        var bytes = global::System.Runtime.InteropServices.MemoryMarshal.AsBytes(");
            sb.AppendLine("            global::System.Runtime.InteropServices.MemoryMarshal.CreateSpan(ref buffer, 1));");
            sb.AppendLine("        var nul = bytes.IndexOf((byte)0);");
            sb.AppendLine("        return global::System.Text.Encoding.UTF8.GetString(nul < 0 ? bytes : bytes.Slice(0, nul));");
            sb.AppendLine("    }");
            sb.AppendLine();
            sb.AppendLine("    private static void GeneratedUtf8Set<TBuf>(ref TBuf buffer, string value, string property) where TBuf : struct");
            sb.AppendLine("    {");
            sb.AppendLine("        var bytes = global::System.Runtime.InteropServices.MemoryMarshal.AsBytes(");
            sb.AppendLine("            global::System.Runtime.InteropServices.MemoryMarshal.CreateSpan(ref buffer, 1));");
            sb.AppendLine("        var text = value ?? string.Empty;");
            sb.AppendLine("        var needed = global::System.Text.Encoding.UTF8.GetByteCount(text);");
            sb.AppendLine("        if (needed > bytes.Length - 1)");
            sb.AppendLine("            throw new global::System.ArgumentException(");
            sb.AppendLine("                $\"{property} holds {bytes.Length - 1} bytes of UTF-8, and the value needs {needed}.\", property);");
            sb.AppendLine("        bytes.Clear();");
            sb.AppendLine("        global::System.Text.Encoding.UTF8.GetBytes(text.AsSpan(), bytes);");
            sb.AppendLine("    }");
        }

        sb.AppendLine();
        foreach (var slot in slots)
        {
            sb.AppendLine($"    private ref {slot.TypeName} {slot.Current}(out bool live) =>");
            sb.AppendLine($"        ref GeneratedStorage<{slot.TypeName}>({slot.Cid}, ref {slot.State}, out live);");
        }
        sb.AppendLine();

        sb.AppendLine($"    {overrideModifier} override void GeneratedBind(global::KernelEngine.Framework.ScriptHost scriptHost)");
        sb.AppendLine("    {");
        sb.AppendLine("        base.GeneratedBind(scriptHost);");
        foreach (var t in signalTypes)
            sb.AppendLine($"        scriptHost.DeclareSignal<{t}>();");
        foreach (var slot in slots)
        {
            var resolveCid = isNative
                ? $"scriptHost.CidOfName(\"{slot.ComponentName}\")"
                : $"scriptHost.RegisterComponent<{slot.TypeName}>({slot.NameExpression})";
            sb.AppendLine($"        {slot.Cid} = {resolveCid};");
            sb.AppendLine($"        GeneratedSeed({slot.Cid}, in {slot.State});");
        }
        sb.AppendLine("    }");

        if (!isNative && !slots.IsEmpty)
            EmitSceneApply(sb, slots[0], properties);

        EmitSignalDispatch(sb, classSymbol, overrideModifier);

        sb.AppendLine("}");

        spc.AddSource($"{className}.NodeProperties.g.cs", sb.ToString());
    }

    /// <summary>
    /// Emits the field table the slot struct states: one row per property a scene can write, under
    /// the key <c>EmitSceneApply</c> reads it by, with no default, since a game node's defaults are
    /// the initial values of its properties.
    /// </summary>
    static void EmitLayout(StringBuilder sb, string typeName, ImmutableArray<IPropertySymbol> properties)
    {
        const string ns = "global::KernelEngine.Ecs";
        sb.AppendLine();
        sb.AppendLine($"        private static readonly {ns}.ComponentField[] s_fields = DescribeFields();");
        sb.AppendLine();
        sb.AppendLine($"        public static global::System.ReadOnlySpan<{ns}.ComponentField> Fields => s_fields;");
        sb.AppendLine();
        sb.AppendLine($"        private static {ns}.ComponentField[] DescribeFields()");
        sb.AppendLine("        {");
        sb.AppendLine($"            var v = default({typeName});");
        sb.AppendLine("            return");
        sb.AppendLine("            [");
        foreach (var p in properties)
        {
            if (KindOf(p.Type) is not { } kind) continue;
            sb.AppendLine($"                {ns}.ComponentFields.Row(ref v, ref v.{p.Name}, \"{SnakeCase(p.Name)}\", {ns}.ComponentFieldKind.{kind}, {ns}.ComponentFieldValue.None),");
        }
        sb.AppendLine("            ];");
        sb.AppendLine("        }");
    }

    /// <summary>The field kind a property is addressed as, or null for a type a scene cannot write.</summary>
    static string? KindOf(ITypeSymbol t)
    {
        if (t.TypeKind == TypeKind.Enum) return "Int";
        if (t.SpecialType == SpecialType.System_String) return "String";
        return t.ToDisplayString() switch
        {
            "float" or "double" => "Float",
            "bool" => "Bool",
            "int" or "uint" or "long" or "short" or "byte" => "Int",
            "System.Numerics.Vector2" => "Vec2",
            "System.Numerics.Vector3" => "Vec3",
            "System.Numerics.Vector4" => "Vec4",
            "System.Numerics.Quaternion" => "Quat",
            _ => null,
        };
    }

    const int DefaultTextCapacity = 128;

    static int TextCapacityOf(IPropertySymbol p)
    {
        var attr = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NodeTextAttribute");
        if (attr is null || attr.ConstructorArguments.Length == 0) return DefaultTextCapacity;
        return attr.ConstructorArguments[0].Value is int n && n > 1 ? n : DefaultTextCapacity;
    }

    /// <summary>
    /// Returns the name in snake case: a word starts at an uppercase letter unless the previous
    /// character is a digit, or is uppercase while the next character is not lowercase. The result
    /// is the registered component name of a game node and the key a scene file uses for it.
    /// </summary>
    static string SnakeCase(string name)
    {
        var sb = new StringBuilder(name.Length + 4);
        for (var i = 0; i < name.Length; i++)
        {
            var ch = name[i];
            if (char.IsUpper(ch))
            {
                var startsWord = i > 0 && !char.IsDigit(name[i - 1])
                    && (!char.IsUpper(name[i - 1])
                        || (i + 1 < name.Length && !char.IsUpper(name[i + 1])));
                if (startsWord) sb.Append('_');
                sb.Append(char.ToLowerInvariant(ch));
            }
            else sb.Append(ch);
        }
        return sb.ToString();
    }

    /// <summary>
    /// Emits the static <c>RegisterSceneApply</c> of a game node: it registers the component under
    /// the node type's qualified name, the type's short name as an alias a scene may write while
    /// no other component answers to it, and an apply callback that reads each property of a
    /// supported type from the block by its snake case key. A property of any other type has no scene key.
    /// </summary>
    static void EmitSceneApply(StringBuilder sb, Slot slot, ImmutableArray<IPropertySymbol> properties)
    {
        sb.AppendLine();
        sb.AppendLine("    /// <summary>Registers this node's component and the scene-file apply for it.</summary>");
        sb.AppendLine("    internal static void RegisterSceneApply(global::KernelEngine.Framework.World world,"
            + " global::KernelEngine.Ecs.IEcsRegistry ecs)");
        sb.AppendLine("    {");
        sb.AppendLine($"        var cid = ecs.RegisterComponent<{slot.TypeName}>({slot.NameExpression});");
        sb.AppendLine("        world.RegisterComponentAlias(GeneratedComponentAlias, GeneratedComponentName);");
        sb.AppendLine($"        world.RegisterComponentApply(cid, static (ref {slot.TypeName} comp,"
            + " in global::KernelEngine.Ecs.VariantReader reader) =>");
        sb.AppendLine("        {");
        foreach (var p in properties)
        {
            var key = SnakeCase(p.Name);
            var t = p.Type;
            if (t.TypeKind == TypeKind.Enum)
            {
                sb.AppendLine($"            if (reader.TryGetString(\"{key}\", out var s_{key}) && global::System.Enum.TryParse<{t.ToDisplayString()}>(s_{key}, true, out var e_{key}))");
                sb.AppendLine($"                comp.{p.Name} = e_{key};");
                continue;
            }
            if (t.SpecialType == SpecialType.System_String)
            {
                sb.AppendLine($"            if (reader.TryGetString(\"{key}\", out var v_{key}))");
                sb.AppendLine($"                GeneratedUtf8Set(ref comp.{p.Name}, v_{key} ?? string.Empty, \"{p.Name}\");");
                continue;
            }

            var read = t.ToDisplayString() switch
            {
                "float" or "double" => $"reader.TryGetFloat(\"{key}\", out var v_{key})",
                "bool" => $"reader.TryGetBool(\"{key}\", out var v_{key})",
                "int" or "uint" or "long" or "short" or "byte" => $"reader.TryGetInt(\"{key}\", out var v_{key})",
                "System.Numerics.Vector2" => $"reader.TryGetVec2(\"{key}\", out var v_{key})",
                "System.Numerics.Vector3" => $"reader.TryGetVec3(\"{key}\", out var v_{key})",
                "System.Numerics.Vector4" => $"reader.TryGetVec4(\"{key}\", out var v_{key})",
                "System.Numerics.Quaternion" => $"reader.TryGetQuat(\"{key}\", out var v_{key})",
                _ => null,
            };
            if (read is null) continue;
            var cast = t.ToDisplayString() switch
            {
                "double" => $"(double)v_{key}",
                "int" or "uint" or "long" or "short" or "byte" => $"({t.ToDisplayString()})v_{key}",
                "string" => $"v_{key} ?? string.Empty",
                _ => $"v_{key}",
            };
            sb.AppendLine($"            if ({read}) comp.{p.Name} = {cast};");
        }
        sb.AppendLine("        });");
        sb.AppendLine("    }");
    }

    /// <summary>
    /// One component of a node type's set: the native struct backing it (null for a game slot),
    /// the name it is registered under, and its index, which suffixes the names of the state
    /// field, the component id field and the accessor generated for it.
    /// </summary>
    sealed class Slot(INamedTypeSymbol? symbol, string typeName, string componentName, int index)
    {
        public INamedTypeSymbol? Symbol { get; } = symbol;
        public string TypeName { get; } = typeName;
        public string ComponentName { get; } = componentName;
        public int Index { get; } = index;

        public string NameExpression => Symbol is null ? "GeneratedComponentName" : $"\"{ComponentName}\"";

        public string State => $"_generatedState{Index}";
        public string Cid => $"_generatedCid{Index}";
        public string Current => $"GeneratedCurrent{Index}";
    }

    /// <summary>
    /// Whether the component declares a static <c>Default</c> of its own type, the neutral value
    /// its <c>[default:]</c> fields hold, which every constructor of the node then starts from.
    /// </summary>
    static bool HasDefault(INamedTypeSymbol? component) =>
        component is not null && component.GetMembers("Default").OfType<IPropertySymbol>()
            .Any(d => d.IsStatic && SymbolEqualityComparer.Default.Equals(d.Type, component));

    static INamedTypeSymbol? NamedComponentOf(AttributeData? attr) =>
        attr?.NamedArguments.FirstOrDefault(kv => kv.Key == "Component").Value.Value as INamedTypeSymbol;

    static Slot? ResolveSlot(SourceProductionContext spc, IPropertySymbol property, ImmutableArray<Slot> slots,
        bool isNative, string fieldName, INamedTypeSymbol? pinned)
    {
        if (slots.Length == 1) return slots[0];

        if (pinned is not null)
        {
            var named = slots.FirstOrDefault(s => SymbolEqualityComparer.Default.Equals(s.Symbol, pinned));
            if (named is not null) return named;
            spc.ReportDiagnostic(Diagnostic.Create(UnknownComponentRule, property.Locations.FirstOrDefault(),
                property.Name, pinned.ToDisplayString()));
            return null;
        }

        var matches = slots.Where(s => s.Symbol?.GetMembers(fieldName).OfType<IFieldSymbol>().Any() == true)
            .ToImmutableArray();
        if (matches.Length == 1) return matches[0];

        spc.ReportDiagnostic(Diagnostic.Create(AmbiguousComponentRule, property.Locations.FirstOrDefault(),
            property.Name, matches.IsEmpty ? "none" : matches.Length.ToString(), fieldName));
        return null;
    }

    static bool DerivesFromNode(INamedTypeSymbol symbol)
    {
        for (var t = symbol.BaseType; t is not null; t = t.BaseType)
            if (t.Name == "Node") return true;
        return false;
    }

    /// <summary>
    /// Returns the read and write conversions between a property type and the type of its backing
    /// field, or null when no conversion applies. Only <c>bool</c> over <c>byte</c> converts; any
    /// other difference of type is left for the caller to report.
    /// </summary>
    static (Func<string, string> read, Func<string, string> write)? CoercionFor(ITypeSymbol propertyType, ITypeSymbol fieldType)
    {
        if (propertyType.SpecialType == SpecialType.System_Boolean && fieldType.SpecialType == SpecialType.System_Byte)
            return (expr => $"{expr} != 0", expr => $"(byte)({expr} ? 1 : 0)");
        return null;
    }

    static readonly DiagnosticDescriptor AmbiguousComponentRule = new(
        id: "KESG002",
        title: "Node property does not resolve to exactly one of the node's components",
        messageFormat: "Property '{0}' matches {1} of this node's components on field '{2}'; name the intended one with [NativeField(..., Component = typeof(...))]",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor UnknownComponentRule = new(
        id: "KESG003",
        title: "Node property names a component the node does not declare",
        messageFormat: "Property '{0}' names component '{1}', which this node does not declare with [GeneratedNodeComponent]",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    /// <summary>
    /// A behavior method a node may declare, the <c>Node</c> override its dispatch is written into
    /// and the flag that tells the host the type has one.
    /// </summary>
    sealed class Hook(string method, string @override, string flag)
    {
        public string Method { get; } = method;
        public string Override { get; } = @override;
        public string Flag { get; } = flag;
    }

    static readonly Hook[] Hooks =
    [
        new("Update", "OnUpdate", "HasBehavior"),
        new("FixedUpdate", "OnFixedUpdate", "HasFixedBehavior"),
    ];

    /// <summary>
    /// Emits the flag and the dispatch of one behavior hook: a declared <c>Hook.Method</c> taking a
    /// <c>View</c> and borrows is called from a generated <c>Hook.Override</c>, and a hand-written
    /// override counts as the hook too. Reports <c>KESG005</c> for a method that cannot be
    /// dispatched and <c>KESG006</c> for a parameter that is not a borrow, and returns the borrow
    /// parameters of the dispatched method.
    /// </summary>
    static ImmutableArray<IParameterSymbol> EmitHook(SourceProductionContext spc, StringBuilder sb,
        INamedTypeSymbol classSymbol, string overrideModifier, Hook hook, out bool declared, out bool handWritten)
    {
        handWritten = classSymbol.GetMembers(hook.Override).OfType<IMethodSymbol>()
            .Any(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol) && m.IsOverride);

        var declaredMethods = classSymbol.GetMembers(hook.Method).OfType<IMethodSymbol>()
            .Where(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol))
            .ToImmutableArray();

        var method = declaredMethods.FirstOrDefault(m =>
            m.Parameters.Length > 0 && m.Parameters[0].Type.Name == "View");

        foreach (var m in declaredMethods)
        {
            if (SymbolEqualityComparer.Default.Equals(m, method)) continue;
            spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, m.Locations.FirstOrDefault(),
                classSymbol.Name, hook.Method, "its first parameter is not a View"));
        }

        if (method is not null && handWritten)
            spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, method.Locations.FirstOrDefault(),
                classSymbol.Name, hook.Method, $"it also overrides {hook.Override}, which takes precedence"));

        if (method is not null)
            foreach (var pp in method.Parameters.Skip(1))
                if (BorrowKindOf(pp.Type) is null)
                    spc.ReportDiagnostic(Diagnostic.Create(UpdateParameterRule, pp.Locations.FirstOrDefault(),
                        pp.Name, hook.Method, pp.Type.ToDisplayString()));

        declared = handWritten || method is not null;
        if (!declared) return ImmutableArray<IParameterSymbol>.Empty;

        sb.AppendLine($"    {overrideModifier} override bool {hook.Flag} => true;");
        sb.AppendLine();

        if (method is null || handWritten) return ImmutableArray<IParameterSymbol>.Empty;

        sb.AppendLine($"    {overrideModifier} override void {hook.Override}(in global::KernelEngine.Framework.View view)");
        sb.AppendLine("    {");
        var args = new List<string> { "in view" };
        foreach (var pp in method.Parameters.Skip(1))
        {
            var kind = BorrowKindOf(pp.Type);
            if (kind is null) continue;
            var arg = ((INamedTypeSymbol)pp.Type).TypeArguments[0].ToDisplayString();
            if (kind == "Emit") { args.Add($"BorrowEmit<{arg}>()"); continue; }
            var nameAttr = pp.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NodeNameAttribute");
            var nodeName = nameAttr is not null ? (string)nameAttr.ConstructorArguments[0].Value! : "";
            var reach = ReachOf((INamedTypeSymbol)pp.Type)!;
            args.Add($"new global::KernelEngine.Framework.{kind}<{arg}>("
                + $"Borrow<{arg}>(\"{nodeName}\", global::KernelEngine.Framework.ScriptBorrow.{reach}))");
        }
        sb.AppendLine($"        {hook.Method}({string.Join(", ", args)});");
        sb.AppendLine("    }");
        sb.AppendLine();

        return method.Parameters.Skip(1).Where(pp => BorrowKindOf(pp.Type) is not null).ToImmutableArray();
    }

    /// <summary>
    /// Emits <c>CollectHookComponents</c> for the hooks whose access <see cref="BehaviorAccess"/>
    /// could read. It answers only for an instance of exactly this class, since a subclass that is
    /// not <c>partial</c> may replace a hook's body.
    /// </summary>
    static void EmitHookComponents(StringBuilder sb, string className, string overrideModifier,
        List<(Hook Hook, List<BehaviorAccess.Use> Uses, ImmutableArray<IParameterSymbol> Borrows)> precise)
    {
        sb.AppendLine($"    {overrideModifier} override bool CollectHookComponents(global::System.Collections.Generic.List<global::KernelEngine.Framework.NodeComponentUse> into, bool fixedStep)");
        sb.AppendLine("    {");
        sb.AppendLine($"        if (GetType() != typeof({className})) return false;");
        foreach (var (hook, uses, borrows) in precise)
        {
            sb.AppendLine($"        if ({(hook.Method == "FixedUpdate" ? "fixedStep" : "!fixedStep")})");
            sb.AppendLine("        {");
            foreach (var u in uses)
                sb.AppendLine($"            into.Add(new({u.NameExpression}, {(u.Writes ? "true" : "false")}, {(u.Owned ? "true" : "false")}));");
            sb.AppendLine("            return true;");
            sb.AppendLine("        }");
        }
        sb.AppendLine("        return false;");
        sb.AppendLine("    }");
        sb.AppendLine();
    }

    static readonly DiagnosticDescriptor ForeignNodeRule = new(
        id: "KESG009",
        title: "Behavior hook reaches a node the scheduler cannot see",
        messageFormat: "'{0}.{1}': {2}",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor WholeTypeAccessRule = new(
        id: "KESG008",
        title: "Behavior hook declares every component of its type",
        messageFormat: "'{0}.{1}' declares every component of '{0}' because {2}; the scheduler cannot run it beside other writers of those components",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Info,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor UpdateNotDispatchedRule = new(
        id: "KESG005",
        title: "Behavior method will never run",
        messageFormat: "'{0}' declares {1} but {2}, so no dispatch is generated and the method never runs",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor UpdateParameterRule = new(
        id: "KESG006",
        title: "Behavior parameter is not a borrow",
        messageFormat: "Parameter '{0}' of {1} is {2}, which is not a borrow wrapper or Emit<T>; every access a behavior has must be a borrow parameter",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor NoCoercionRule = new(
        id: "KESG001",
        title: "No coercion rule for node property/native field type mismatch",
        messageFormat: "Property '{0}' is {1} but its backing field is {2}, and no coercion rule connects them",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    /// <summary>
    /// Every payload type the class handles through <c>On</c> or emits through an <c>Emit</c>
    /// parameter, declared by <c>GeneratedBind</c> so a scene may connect it.
    /// </summary>
    static string[] SignalTypesOf(INamedTypeSymbol classSymbol, ImmutableArray<IParameterSymbol> borrows) =>
        SignalHandlersOf(classSymbol)
            .Select(m => m.Parameters[0].Type.ToDisplayString())
            .Concat(borrows
                .Where(b => BorrowKindOf(b.Type) == "Emit")
                .Select(b => ((INamedTypeSymbol)b.Type).TypeArguments[0].ToDisplayString()))
            .Distinct()
            .ToArray();

    /// <summary>Every <c>On(in T)</c> this type declares itself.</summary>
    static IMethodSymbol[] SignalHandlersOf(INamedTypeSymbol classSymbol) =>
        classSymbol.GetMembers("On").OfType<IMethodSymbol>()
            .Where(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol)
                && m.Parameters.Length == 1
                && m.Parameters[0].Type.IsUnmanagedType
                && m.Parameters[0].Type.TypeKind == TypeKind.Struct)
            .ToArray();

    /// <summary>
    /// Emits <c>GeneratedDeliverSignal</c>, which calls the <c>On</c> handler whose parameter
    /// type is the payload type delivered. A class with no handler emits nothing.
    /// </summary>
    static void EmitSignalDispatch(StringBuilder sb, INamedTypeSymbol classSymbol, string overrideModifier)
    {
        var handlers = SignalHandlersOf(classSymbol);
        if (handlers.Length == 0) return;

        sb.AppendLine();
        sb.AppendLine($"    {overrideModifier} override void GeneratedDeliverSignal(global::System.Type payloadType, global::System.ReadOnlySpan<byte> payload)");
        sb.AppendLine("    {");
        sb.AppendLine("        base.GeneratedDeliverSignal(payloadType, payload);");
        foreach (var h in handlers)
        {
            var t = h.Parameters[0].Type.ToDisplayString();
            sb.AppendLine($"        if (payloadType == typeof({t}))");
            sb.AppendLine("        {");
            sb.AppendLine($"            var e = global::System.Runtime.InteropServices.MemoryMarshal.Read<{t}>(payload);");
            sb.AppendLine("            On(in e);");
            sb.AppendLine("        }");
        }
        sb.AppendLine("    }");
    }

    /// <summary>
    /// Returns the name of the borrow a parameter type is: <c>Emit</c>, or a generic wrapper
    /// carrying a <c>NodeBorrow</c> attribute. Null when it is neither.
    /// </summary>
    static string? BorrowKindOf(ITypeSymbol type)
    {
        if (type is not INamedTypeSymbol named || named.TypeArguments.Length != 1) return null;
        if (named.Name == "Emit") return "Emit";
        return ReachOf(named) is not null ? named.Name : null;
    }

    /// <summary>
    /// The <c>ScriptBorrow</c> member a borrow wrapper resolves with, or null when the type is
    /// not a borrow wrapper.
    /// </summary>
    static string? ReachOf(INamedTypeSymbol named)
    {
        var marker = named.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NodeBorrowAttribute");
        if (marker is null || marker.ConstructorArguments.Length != 1) return null;
        var arg = marker.ConstructorArguments[0];
        return (arg.Type as INamedTypeSymbol)?.GetMembers().OfType<IFieldSymbol>()
            .FirstOrDefault(f => f.HasConstantValue && Equals(f.ConstantValue, arg.Value))?.Name;
    }
}
