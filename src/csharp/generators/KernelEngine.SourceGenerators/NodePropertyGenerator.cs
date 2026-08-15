using System;
using System.Collections.Immutable;
using System.Linq;
using System.Text;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace KernelEngine.SourceGenerators;

[Generator]
public sealed class NodePropertyGenerator : IIncrementalGenerator
{
    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        var propertyOwners = context.SyntaxProvider.CreateSyntaxProvider(
            static (node, _) => node is PropertyDeclarationSyntax { Parent: ClassDeclarationSyntax } p && IsPartialAutoProperty(p),
            static (ctx, _) => (ClassDeclarationSyntax)ctx.Node.Parent!);

        // A node whose only generated member is its behavior dispatch declares no
        // partial property at all, so property syntax alone would never see it and
        // its Update would silently never run.
        var behaviorOwners = context.SyntaxProvider.CreateSyntaxProvider(
            static (node, _) => node is MethodDeclarationSyntax { Parent: ClassDeclarationSyntax c } m
                && (m.Identifier.ValueText == "Update" || m.Identifier.ValueText == "On")
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

    static void Generate(SourceProductionContext spc, ClassDeclarationSyntax classDecl, Compilation compilation)
    {
        var model = compilation.GetSemanticModel(classDecl.SyntaxTree);
        if (model.GetDeclaredSymbol(classDecl) is not INamedTypeSymbol classSymbol) return;
        if (!DerivesFromNode(classSymbol)) return;

        // Without partial there is nowhere to emit dispatch into, so a behavior on a
        // sealed-off class would simply never be called with nothing said about it.
        if (!classDecl.Modifiers.Any(SyntaxKind.PartialKeyword))
        {
            if (classSymbol.GetMembers("Update").OfType<IMethodSymbol>().Any(m =>
                    SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol) && m.Parameters.Length > 0))
                spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, classDecl.Identifier.GetLocation(),
                    classSymbol.Name, "the class is not partial"));
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

        // protected internal members (OnBind, HasBehavior) keep protected internal
        // when overridden from Node's own assembly (Framework) — only a CROSS-assembly
        // override is required to narrow to plain protected. Node3D is the first
        // generated type to live in the same assembly as Node itself; every other
        // generated/hand-written node type lives in a domain assembly (Render.Webgpu,
        // Physics, ...), where narrowing is mandatory, not optional.
        INamedTypeSymbol? nodeType = classSymbol.BaseType;
        while (nodeType is not null && nodeType.Name != "Node") nodeType = nodeType.BaseType;
        var overrideModifier = nodeType is not null && SymbolEqualityComparer.Default.Equals(nodeType.ContainingAssembly, classSymbol.ContainingAssembly)
            ? "protected internal"
            : "protected";

        // A node type is a component SET: one slot per declared component, each with its
        // own backing state and cid. A game-authored type declares none, and gets a single
        // synthesized slot instead — the same shape, so nothing below branches on it twice.
        var isNative = markers.Length > 0;
        var slots = isNative
            ? markers.Select((m, i) => new Slot(
                    (INamedTypeSymbol)m.ConstructorArguments[0].Value!,
                    ((INamedTypeSymbol)m.ConstructorArguments[0].Value!).ToDisplayString(),
                    (string)m.ConstructorArguments[1].Value!,
                    i))
                .ToImmutableArray()
            // A game type's component is named after the node, in the same
            // snake_case a native one uses: a scene addresses [entity.paddle]
            // without knowing which language the node behind it was written in.
            // Its struct is nested and private — it belongs to the node visibly,
            // in a stack trace as much as in the file, and pollutes no namespace.
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
            // A string is stored as a fixed UTF-8 buffer, not a managed reference: the
            // component has to be plain memory for a language other than this one to
            // read it at all. Its capacity is the node author's call — see NodeText.
            foreach (var p in properties.Where(p => p.Type.SpecialType == SpecialType.System_String))
            {
                sb.AppendLine($"    [global::System.Runtime.CompilerServices.InlineArray({TextCapacityOf(p)})]");
                sb.AppendLine($"    private struct {p.Name}Buffer {{ private byte _first; }}");
                sb.AppendLine();
            }

            sb.AppendLine($"    private struct {slots[0].TypeName}");
            sb.AppendLine("    {");
            foreach (var p in properties)
                sb.AppendLine(p.Type.SpecialType == SpecialType.System_String
                    ? $"        public {p.Name}Buffer {p.Name};"
                    : $"        public {p.Type.ToDisplayString()} {p.Name};");
            sb.AppendLine("    }");
            sb.AppendLine();
        }

        foreach (var slot in slots)
        {
            sb.AppendLine($"    private {slot.TypeName} {slot.State};");
            sb.AppendLine($"    private uint {slot.Cid};");
        }
        sb.AppendLine();

        // Node.HasBehavior used to be discovered by reflecting on the instance at
        // bind time; it is now a compile-time decision. The user's own partial
        // declares OnUpdate (or doesn't) — that's a fact this generator can see
        // in the same syntax pass, so it emits the override here instead of the
        // runtime ever asking "does this type have OnUpdate" again.
        var hasOnUpdate = classSymbol.GetMembers("OnUpdate").OfType<IMethodSymbol>()
            .Any(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol) && m.IsOverride);

        // A borrow-shaped Update is the model's signature-as-access-list form: the
        // parameters ARE the reach. Dispatch is emitted here so the user's method
        // stays free of resolution code and the reach stays readable in the signature.
        var declaredUpdates = classSymbol.GetMembers("Update").OfType<IMethodSymbol>()
            .Where(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol))
            .ToImmutableArray();

        var updateMethod = declaredUpdates.FirstOrDefault(m =>
            m.Parameters.Length > 0 && m.Parameters[0].Type.Name == "View");

        // Every way a behavior can be written and silently not run gets named here.
        // The failure this replaces surfaced only as a node that did nothing on screen,
        // with no build output pointing at the method that was skipped.
        foreach (var m in declaredUpdates)
        {
            if (SymbolEqualityComparer.Default.Equals(m, updateMethod)) continue;
            spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, m.Locations.FirstOrDefault(),
                classSymbol.Name, "its first parameter is not a View"));
        }

        if (updateMethod is not null && hasOnUpdate)
            spc.ReportDiagnostic(Diagnostic.Create(UpdateNotDispatchedRule, updateMethod.Locations.FirstOrDefault(),
                classSymbol.Name, "it also overrides OnUpdate, which takes precedence"));

        if (updateMethod is not null)
            foreach (var pp in updateMethod.Parameters.Skip(1))
                if (BorrowKindOf(pp.Type) is null)
                    spc.ReportDiagnostic(Diagnostic.Create(UpdateParameterRule, pp.Locations.FirstOrDefault(),
                        pp.Name, pp.Type.ToDisplayString()));

        var borrows = updateMethod is null
            ? ImmutableArray<IParameterSymbol>.Empty
            : updateMethod.Parameters.Skip(1)
                .Where(pp => BorrowKindOf(pp.Type) is not null)
                .ToImmutableArray();

        if (hasOnUpdate || updateMethod is not null)
        {
            sb.AppendLine($"    {overrideModifier} override bool HasBehavior => true;");
            sb.AppendLine();
        }

        if (updateMethod is not null && !hasOnUpdate)
        {
            sb.AppendLine($"    {overrideModifier} override void OnUpdate(in global::KernelEngine.Framework.View view)");
            sb.AppendLine("    {");
            var args = new List<string> { "in view" };
            foreach (var pp in updateMethod.Parameters.Skip(1))
            {
                var kind = BorrowKindOf(pp.Type);
                if (kind is null) continue;
                var arg = ((INamedTypeSymbol)pp.Type).TypeArguments[0].ToDisplayString();
                // An Emit borrow resolves by payload type, not by node name: it is
                // the right to raise a signal from this node, and this node is
                // already known.
                if (kind == "Emit") { args.Add($"BorrowEmit<{arg}>()"); continue; }
                var nameAttr = pp.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NodeNameAttribute");
                var nodeName = nameAttr is not null ? (string)nameAttr.ConstructorArguments[0].Value! : pp.Name;
                args.Add($"Borrow{kind}<{arg}>(\"{nodeName}\")");
            }
            sb.AppendLine($"        Update({string.Join(", ", args)});");
            sb.AppendLine("    }");
            sb.AppendLine();
        }

        sb.AppendLine($"    {overrideModifier} override void CollectBehaviorComponents(global::System.Collections.Generic.List<string> into)");
        sb.AppendLine("    {");
        sb.AppendLine("        base.CollectBehaviorComponents(into);");
        foreach (var slot in slots)
            sb.AppendLine($"        into.Add(\"{slot.ComponentName}\");");
        foreach (var b in borrows)
        {
            // An Emit borrow reaches no component: emission lands in the signal
            // bus's frame storage, which the scheduler does not order on.
            if (BorrowKindOf(b.Type) == "Emit") continue;
            foreach (var cn in ComponentNamesOf((INamedTypeSymbol)((INamedTypeSymbol)b.Type).TypeArguments[0]))
                sb.AppendLine($"        into.Add(\"{cn}\");");
        }
        sb.AppendLine("    }");
        sb.AppendLine();

        var needsUtf8Helpers = false;

        // Scene authoring writes the whole component once, not once per property:
        // a per-property read-modify-write collapses to last-write-wins whenever the
        // component write is deferred, because every read still sees the pre-write
        // value. Each plan records how to place one property into a local copy.

        foreach (var p in properties)
        {
            var wholeAttr = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NativeWholeAttribute");
            var fieldAttr = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NativeFieldAttribute");
            var declaredFieldName = fieldAttr is not null ? (string)fieldAttr.ConstructorArguments[0].Value! : p.Name;
            var pinned = NamedComponentOf(wholeAttr) ?? NamedComponentOf(fieldAttr);

            var slot = ResolveSlot(spc, p, slots, isNative, declaredFieldName, wholeAttr is not null, pinned);
            if (slot is null) continue;

            var backingType = slot.TypeName;
            var backingTypeSymbol = slot.Symbol;

            if (wholeAttr is not null)
            {
                // The whole backing struct, bit-cast — not a per-field read/write.
                // Same shape as a hand-written whole-struct property (Node3D's
                // LocalTransform before this became generatable), except the cast
                // replaces field-by-field assignment so the write stays atomic.
                var propType = p.Type.ToDisplayString();
                sb.AppendLine($"    public partial {propType} {p.Name}");
                sb.AppendLine("    {");
                sb.AppendLine($"        get => global::System.Runtime.CompilerServices.Unsafe.BitCast<{backingType}, {propType}>({slot.Current}());");
                sb.AppendLine("        set");
                sb.AppendLine("        {");
                sb.AppendLine($"            var s = global::System.Runtime.CompilerServices.Unsafe.BitCast<{propType}, {backingType}>(value);");
                sb.AppendLine($"            if (IsBound) GeneratedSet({slot.Cid}, s); else {slot.State} = s;");
                sb.AppendLine("        }");
                sb.AppendLine("    }");
                continue;
            }

            var fieldName = isNative ? declaredFieldName : p.Name;
            var fieldSymbol = backingTypeSymbol?.GetMembers(fieldName).OfType<IFieldSymbol>().FirstOrDefault();
            // ClangSharp backs a C `float x[N]` with a generated `_x_e__FixedBuffer` type —
            // only THAT shape indexes by [i]; a named ke_vecN/ke_quat field (below) is a
            // bit-cast coercion instead, even though its C# property is also Vector2/3/4.
            var isFixedBuffer = fieldSymbol is not null && fieldSymbol.Type.Name.EndsWith("_e__FixedBuffer");

            // A `char[N]` component field projected as a string. The buffer's own
            // capacity is the truncation point — it is the component's ABI, so the
            // property cannot widen it, only refuse to overflow it.
            // A game type's component has no C header behind it, so the buffer that
            // makes a string storable is generated here, sized by the node's author.
            if (p.Type.SpecialType == SpecialType.System_String && !isNative)
            {
                needsUtf8Helpers = true;
                sb.AppendLine($"    public partial string {p.Name}");
                sb.AppendLine("    {");
                sb.AppendLine("        get");
                sb.AppendLine("        {");
                sb.AppendLine($"            var s = {slot.Current}();");
                sb.AppendLine($"            return GeneratedUtf8Get(ref s.{p.Name});");
                sb.AppendLine("        }");
                sb.AppendLine("        set");
                sb.AppendLine("        {");
                sb.AppendLine($"            var s = {slot.Current}();");
                sb.AppendLine($"            GeneratedUtf8Set(ref s.{p.Name}, value, \"{p.Name}\");");
                sb.AppendLine($"            if (IsBound) GeneratedSet({slot.Cid}, s); else {slot.State} = s;");
                sb.AppendLine("        }");
                sb.AppendLine("    }");
                continue;
            }

            if (p.Type.SpecialType == SpecialType.System_String && isFixedBuffer)
            {
                needsUtf8Helpers = true;
                sb.AppendLine($"    public partial string {p.Name}");
                sb.AppendLine("    {");
                sb.AppendLine("        get");
                sb.AppendLine("        {");
                sb.AppendLine($"            var s = {slot.Current}();");
                sb.AppendLine($"            return GeneratedUtf8Get(ref s.{fieldName});");
                sb.AppendLine("        }");
                sb.AppendLine("        set");
                sb.AppendLine("        {");
                sb.AppendLine($"            var s = {slot.Current}();");
                sb.AppendLine($"            GeneratedUtf8Set(ref s.{fieldName}, value, \"{p.Name}\");");
                sb.AppendLine($"            if (IsBound) GeneratedSet({slot.Cid}, s); else {slot.State} = s;");
                sb.AppendLine("        }");
                sb.AppendLine("    }");
                continue;
            }

            var arity = isNative && isFixedBuffer ? VectorArity(p.Type) : null;
            var coercion = arity is null && fieldSymbol is not null ? CoercionFor(p.Type, fieldSymbol.Type) : null;

            if (arity is null && fieldSymbol is not null && coercion is null
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
            sb.AppendLine($"            var s = {slot.Current}();");
            sb.AppendLine(arity is int rn
                ? $"            return new(" + string.Join(", ", Enumerable.Range(0, rn).Select(i => $"s.{fieldName}[{i}]")) + ");"
                : coercion is not null
                    ? $"            return {coercion.Value.read("s." + fieldName)};"
                    : $"            return s.{fieldName};");
            sb.AppendLine("        }");
            sb.AppendLine("        set");
            sb.AppendLine("        {");
            sb.AppendLine($"            var s = {slot.Current}();");
            if (arity is int wn)
                foreach (var i in Enumerable.Range(0, wn))
                    sb.AppendLine($"            s.{fieldName}[{i}] = value.{VectorLanes[i]};");
            else if (coercion is not null)
                sb.AppendLine($"            s.{fieldName} = {coercion.Value.write("value")};");
            else
                sb.AppendLine($"            s.{fieldName} = value;");
            sb.AppendLine($"            if (IsBound) GeneratedSet({slot.Cid}, s); else {slot.State} = s;");
            sb.AppendLine("        }");
            sb.AppendLine("    }");
        }

        if (needsUtf8Helpers)
        {
            // Generic over the inline-array type so one pair serves every char[N]
            // field regardless of its capacity: CreateSpan(ref buf, 1) + AsBytes
            // yields exactly sizeof(TBuf) bytes, which IS N for a char buffer.
            sb.AppendLine();
            sb.AppendLine("    private static string GeneratedUtf8Get<TBuf>(ref TBuf buffer) where TBuf : struct");
            sb.AppendLine("    {");
            sb.AppendLine("        var bytes = global::System.Runtime.InteropServices.MemoryMarshal.AsBytes(");
            sb.AppendLine("            global::System.Runtime.InteropServices.MemoryMarshal.CreateSpan(ref buffer, 1));");
            sb.AppendLine("        var nul = bytes.IndexOf((byte)0);");
            sb.AppendLine("        return global::System.Text.Encoding.UTF8.GetString(nul < 0 ? bytes : bytes.Slice(0, nul));");
            sb.AppendLine("    }");
            sb.AppendLine();
            // Refuses rather than truncates. The buffer's capacity is the component's
            // ABI, so a value that does not fit is a fact the caller has to hear now: a
            // silently shortened path is a file that fails to open much later, pointing
            // at nothing that explains it.
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
            sb.AppendLine($"    private {slot.TypeName} {slot.Current}() =>");
            sb.AppendLine($"        IsBound && GeneratedTryGet<{slot.TypeName}>({slot.Cid}, out var s) ? s : {slot.State};");
        }
        sb.AppendLine();

        sb.AppendLine($"    {overrideModifier} override void GeneratedBind(global::KernelEngine.Framework.NodeWorld nodeWorld)");
        sb.AppendLine("    {");
        // A node type deriving from another generated node (MeshRenderer : Node3D)
        // binds TWO components, one per class in the chain, each with its own
        // _generatedCid. Overriding without chaining would leave every base
        // class's component unbound — its cid stays 0 and every write to its
        // properties is silently dropped.
        sb.AppendLine("        base.GeneratedBind(nodeWorld);");
        foreach (var slot in slots)
        {
            var resolveCid = isNative
                ? $"nodeWorld.CidOfName(\"{slot.ComponentName}\")"
                : $"nodeWorld.RegisterComponent<{slot.TypeName}>(\"{slot.ComponentName}\")";
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
    /// Bytes of UTF-8 a string property stores, from its <c>[NodeText]</c> or the
    /// default when it declares none.
    /// </summary>
    /// <remarks>
    /// The default exists so a node that never thought about it still works; it is not a
    /// ceiling anyone is stuck with, because exceeding it throws and names the attribute
    /// that raises it rather than truncating.
    /// </remarks>
    const int DefaultTextCapacity = 128;

    static int TextCapacityOf(IPropertySymbol p)
    {
        var attr = p.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NodeTextAttribute");
        if (attr is null || attr.ConstructorArguments.Length == 0) return DefaultTextCapacity;
        return attr.ConstructorArguments[0].Value is int n && n > 1 ? n : DefaultTextCapacity;
    }

    /// <summary>The name a scene file addresses this node's own component by.</summary>
    /// <remarks>
    /// One rule for engine and game alike: the component of a node is the node's name
    /// in snake_case. A generated name nobody would guess (the old
    /// <c>Namespace.Type_Data</c>) meant a game component could only be authored by
    /// someone who had read the generator.
    /// </remarks>
    static string SnakeCase(string name)
    {
        var sb = new StringBuilder(name.Length + 4);
        for (var i = 0; i < name.Length; i++)
        {
            var ch = name[i];
            if (char.IsUpper(ch))
            {
                // A run of capitals is one word, so UIRoot reads ui_root, not u_i_root;
                // a capital after a digit continues one, so Sprite2D reads sprite2d.
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
    /// Emits the registration that gives a game node's component a scene-file surface:
    /// the cid under the node's own name, plus the apply that fills each declared
    /// property from the block's keys.
    /// </summary>
    /// <remarks>
    /// Static because a scene block is applied before any node of that type exists —
    /// the loader writes component memory first and instantiates the node onto it.
    /// Registering from an instance would always be one step too late.
    /// </remarks>
    static void EmitSceneApply(StringBuilder sb, Slot slot, ImmutableArray<IPropertySymbol> properties)
    {
        sb.AppendLine();
        sb.AppendLine("    /// <summary>Registers this node's component and the scene-file apply for it.</summary>");
        sb.AppendLine("    internal static void RegisterSceneApply(global::KernelEngine.Framework.World world,"
            + " global::KernelEngine.Ecs.IEcsRegistry ecs)");
        sb.AppendLine("    {");
        sb.AppendLine($"        var cid = ecs.RegisterComponent<{slot.TypeName}>(\"{slot.ComponentName}\");");
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
            // A string lands in the property's fixed buffer through the same checked
            // writer the setter uses, so a scene authoring a value too long for the
            // component fails the load instead of storing a truncated one.
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
            // A property whose type the scene vocabulary cannot spell stays code-only
            // rather than getting an encoding invented for it here.
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
    /// The <c>VariantReader</c> accessor that can express <paramref name="type"/>, plus the
    /// conversion from what it yields to the property's own type. Null when the scene-file
    /// variant vocabulary has no representation for the type, which leaves that property
    /// code-only rather than inventing an encoding for it.
    /// </summary>

    /// <summary>
    /// One component of a node type's set: the native struct backing it, the name it is
    /// registered under, and the members generated for it. The index suffix is what keeps
    /// two components on the same node from colliding on a single state/cid pair.
    /// </summary>
    sealed class Slot(INamedTypeSymbol? symbol, string typeName, string componentName, int index)
    {
        public INamedTypeSymbol? Symbol { get; } = symbol;
        public string TypeName { get; } = typeName;
        public string ComponentName { get; } = componentName;
        public int Index { get; } = index;

        public string State => $"_generatedState{Index}";
        public string Cid => $"_generatedCid{Index}";
        public string Current => $"GeneratedCurrent{Index}";
    }

    static INamedTypeSymbol? NamedComponentOf(AttributeData? attr) =>
        attr?.NamedArguments.FirstOrDefault(kv => kv.Key == "Component").Value.Value as INamedTypeSymbol;

    static Slot? ResolveSlot(SourceProductionContext spc, IPropertySymbol property, ImmutableArray<Slot> slots,
        bool isNative, string fieldName, bool isWhole, INamedTypeSymbol? pinned)
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

        // A whole-struct property names no field, so nothing but an explicit Component can
        // say which of several structs it IS.
        if (isWhole)
        {
            spc.ReportDiagnostic(Diagnostic.Create(UnnamedWholeRule, property.Locations.FirstOrDefault(), property.Name));
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

    static readonly string[] VectorLanes = ["X", "Y", "Z", "W"];

    static int? VectorArity(ITypeSymbol type)
    {
        if (type.ContainingNamespace?.ToDisplayString() != "System.Numerics") return null;
        return type.Name switch { "Vector2" => 2, "Vector3" => 3, "Vector4" => 4, _ => null };
    }

    // ke_vec2/ke_vec3/ke_vec4/ke_quat (KernelEngine.Common.Native) are layout-identical
    // to their System.Numerics counterparts by construction (see kabic's NamedVectorTypes),
    // so the coercion is a bit-cast, not a field-by-field copy.
    static readonly Dictionary<string, string> NativeVectorNames = new()
    {
        ["Vector2"] = "ke_vec2", ["Vector3"] = "ke_vec3", ["Vector4"] = "ke_vec4", ["Quaternion"] = "ke_quat",
    };

    // ke_mesh_handle / ke_material_handle are { uint32_t bits; }; their managed
    // counterparts are readonly record struct H(uint Value). Same size, same single
    // field, so the coercion is a bit-cast like the vector one above.
    static readonly Dictionary<string, string> NativeHandleNames = new()
    {
        ["MeshHandle"] = "ke_mesh_handle", ["MaterialHandle"] = "ke_material_handle",
        ["TextureHandle"] = "ke_texture_handle", ["FontHandle"] = "ke_ui_font_handle",
    };

    static (Func<string, string> read, Func<string, string> write)? CoercionFor(ITypeSymbol propertyType, ITypeSymbol fieldType)
    {
        if (propertyType.SpecialType == SpecialType.System_Boolean && fieldType.SpecialType == SpecialType.System_Byte)
            return (expr => $"{expr} != 0", expr => $"(byte)({expr} ? 1 : 0)");
        // A domain's managed enum and the ClangSharp binding of the same C enum are two
        // declarations of one set of named integers, generated from one header. Their
        // underlying types need not match — kabic picks int, ClangSharp mirrors C's
        // unsigned — but the members and their values do, so the conversion is a cast.
        if (propertyType.TypeKind == TypeKind.Enum && fieldType.TypeKind == TypeKind.Enum)
        {
            var pn = propertyType.ToDisplayString();
            var fn = fieldType.ToDisplayString();
            return (expr => $"({pn}){expr}", expr => $"({fn}){expr}");
        }
        if (NativeHandleNames.TryGetValue(propertyType.Name, out var nativeHandle) && fieldType.Name == nativeHandle)
        {
            var pn = propertyType.ToDisplayString();
            var fn = fieldType.ToDisplayString();
            return (expr => $"global::System.Runtime.CompilerServices.Unsafe.BitCast<{fn}, {pn}>({expr})",
                    expr => $"global::System.Runtime.CompilerServices.Unsafe.BitCast<{pn}, {fn}>({expr})");
        }
        if (propertyType.ContainingNamespace?.ToDisplayString() == "System.Numerics"
            && NativeVectorNames.TryGetValue(propertyType.Name, out var nativeName)
            && fieldType.Name == nativeName)
        {
            var propName = propertyType.ToDisplayString();
            var fieldName = fieldType.ToDisplayString();
            return (expr => $"global::System.Runtime.CompilerServices.Unsafe.BitCast<{fieldName}, {propName}>({expr})",
                    expr => $"global::System.Runtime.CompilerServices.Unsafe.BitCast<{propName}, {fieldName}>({expr})");
        }
        return null;
    }

    static readonly DiagnosticDescriptor AmbiguousComponentRule = new(
        id: "KESG002",
        title: "Node property does not resolve to exactly one of the node's components",
        messageFormat: "Property '{0}' matches {1} of this node's components on field '{2}'; name the intended one with [NativeField(..., Component = typeof(...))]",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor UnnamedWholeRule = new(
        id: "KESG004",
        title: "Whole-struct node property does not say which component it is",
        messageFormat: "Property '{0}' is [NativeWhole] on a node declaring several components, and a whole-struct property names no field to resolve it by; add Component = typeof(...)",
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

    static readonly DiagnosticDescriptor UpdateNotDispatchedRule = new(
        id: "KESG005",
        title: "Behavior method will never run",
        messageFormat: "'{0}' declares Update but {1}, so no dispatch is generated and the method never runs",
        category: "KernelEngine.SourceGenerators",
        DiagnosticSeverity.Error,
        isEnabledByDefault: true);

    static readonly DiagnosticDescriptor UpdateParameterRule = new(
        id: "KESG006",
        title: "Behavior parameter is not a borrow",
        messageFormat: "Parameter '{0}' of Update is {1}, which is not Child<T>, Ref<T>, or Parent<T>; every access a behavior has must be a borrow parameter",
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
    /// Emits the dispatch that turns a delivered signal into a call on this node's
    /// matching <c>On</c> handler. A node with no handler emits nothing, so listening
    /// costs a virtual call only for types that actually listen.
    /// </summary>
    static void EmitSignalDispatch(StringBuilder sb, INamedTypeSymbol classSymbol, string overrideModifier)
    {
        var handlers = classSymbol.GetMembers("On").OfType<IMethodSymbol>()
            .Where(m => SymbolEqualityComparer.Default.Equals(m.ContainingType, classSymbol)
                && m.Parameters.Length == 1
                && m.Parameters[0].Type.IsUnmanagedType
                && m.Parameters[0].Type.TypeKind == TypeKind.Struct)
            .ToArray();
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

    /// <summary>Which borrow a parameter type is, or null when it is not one.</summary>
    static string? BorrowKindOf(ITypeSymbol type)
    {
        if (type is not INamedTypeSymbol named || named.TypeArguments.Length != 1) return null;
        return named.Name switch
        {
            "Child"  => "Child",
            "Ref"    => "Ref",
            "Parent" => "Parent",
            "Emit"   => "Emit",
            _        => null,
        };
    }

    /// <summary>
    /// The ECS component names a node type reaches, read from the markers on it and
    /// its bases. A hand-written type carrying no markers contributes nothing, which
    /// under-declares rather than over-declares its reach.
    /// </summary>
    static IEnumerable<string> ComponentNamesOf(INamedTypeSymbol type)
    {
        for (var t = type; t is not null; t = t.BaseType)
            foreach (var a in t.GetAttributes())
                if (a.AttributeClass?.Name == "GeneratedNodeComponentAttribute" && a.ConstructorArguments.Length > 1)
                    yield return (string)a.ConstructorArguments[1].Value!;
    }
}
