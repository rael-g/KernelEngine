using System.Collections.Generic;
using System.Linq;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Operations;

namespace KernelEngine.SourceGenerators;

/// <summary>
/// Finds the components a behavior hook reaches, by reading the operations of the hook and of the
/// methods of its class it calls. A component is a generated property of the hook's own node,
/// reached through <c>this</c>, or of a node it borrows, reached through the borrow's
/// <c>Node</c> or <c>Value</c>. A node the body creates is not in the world until the wave ends,
/// so touching it reaches nothing. Any other node is one the scheduler cannot see, which is an
/// error. The result is null whenever the body does something the reading cannot follow, and the
/// caller then declares everything the type carries.
/// </summary>
static class BehaviorAccess
{
    /// <summary>One component the hook reaches: the expression naming it at runtime, and whether
    /// the hook writes it.</summary>
    internal sealed class Use(string nameExpression, bool writes, bool owned)
    {
        public string NameExpression { get; } = nameExpression;
        public bool Writes { get; } = writes;
        public bool Owned { get; } = owned;
    }

    /// <summary>Why a hook's access could not be read, and where. <c>Foreign</c> marks a node
    /// reached outside <c>this</c>, a borrow and what the body created, which no declaration can
    /// cover.</summary>
    internal sealed class Unknown(string reason, Location location, bool foreign = false)
    {
        public string Reason { get; } = reason;
        public Location Location { get; } = location;
        public bool Foreign { get; } = foreign;
    }

    enum Holder { Other, Self, Borrowed, Created, Foreign }

    /// <summary>
    /// The components <paramref name="hook"/>, declared on <paramref name="owner"/>, reaches on its
    /// own node, or null when its body cannot be followed, with <paramref name="unknown"/> saying
    /// why: <c>this</c> used other than as the receiver of a member, a call on <c>this</c> to a
    /// method with no source or one a subclass may override, or a property of the node that is
    /// neither generated nor plain state.
    /// </summary>
    internal static List<Use>? Analyze(Compilation compilation, INamedTypeSymbol owner, IMethodSymbol hook, out Unknown? unknown)
    {
        var walk = new Walk(compilation, owner);
        unknown = walk.Visit(hook, hook.Locations.FirstOrDefault() ?? Location.None);
        return unknown is null ? walk.Uses.Select(u => new Use(u.Key.Name, u.Value, u.Key.Owned)).ToList() : null;
    }

    sealed class Walk(Compilation compilation, INamedTypeSymbol owner)
    {
        public readonly Dictionary<(string Name, bool Owned), bool> Uses = new();
        readonly HashSet<IMethodSymbol> visited = new(SymbolEqualityComparer.Default);

        public Unknown? Visit(IMethodSymbol method, Location at)
        {
            if (!visited.Add(method.OriginalDefinition)) return null;
            var syntax = method.DeclaringSyntaxReferences.FirstOrDefault()?.GetSyntax();
            var operation = syntax is null ? null : compilation.GetSemanticModel(syntax.SyntaxTree).GetOperation(syntax);
            if (operation is null) return new($"it calls '{method.Name}', whose body the generator cannot read", at);

            foreach (var op in operation.DescendantsAndSelf())
            {
                var found = op switch
                {
                    IInstanceReferenceOperation self when self.ReferenceKind == InstanceReferenceKind.ContainingTypeInstance && !IsReceiver(self)
                        => new Unknown("it hands 'this' to code the generator does not follow", self.Syntax.GetLocation()),
                    IPropertyReferenceOperation pr when pr.Instance is not null => Member(pr, pr.Instance, null),
                    IInvocationOperation call when call.Instance is not null => Member(call, call.Instance, call.TargetMethod),
                    IArgumentOperation arg when IsNode(arg.Value.Type) => Argument(arg),
                    _ => null,
                };
                if (found is not null) return found;
            }
            return null;
        }

        Unknown? Member(IOperation op, IOperation instance, IMethodSymbol? method)
        {
            var at = op.Syntax.GetLocation();
            var (holder, borrowed) = Classify(instance);
            switch (holder)
            {
                case Holder.Self:
                    return method is null ? Record((IPropertyReferenceOperation)op) : Follow(method, at);
                case Holder.Borrowed:
                    if (method is null)
                    {
                        var pr = (IPropertyReferenceOperation)op;
                        var name = ComponentOf(pr.Property.OriginalDefinition, owner);
                        if (name is not null)
                        {
                            var writes = AccessOf(pr).Writes;
                            Uses[(name, false)] = (Uses.TryGetValue((name, false), out var w) && w) || writes;
                            return null;
                        }
                        if (IsNodeMember(pr.Property) || IsAutoProperty(pr.Property)) return null;
                    }
                    else if (IsNodeMember(method)) return null;
                    DeclareAll(borrowed!);
                    return null;
                case Holder.Foreign:
                    return new($"it reaches a node through '{instance.Syntax}', which is neither this node, a borrow nor one it created; borrow it with a Descendant, an Ancestor or a named borrow parameter instead", at, foreign: true);
                default:
                    return null;
            }
        }

        Unknown? Argument(IArgumentOperation arg)
        {
            var (holder, borrowed) = Classify(arg.Value);
            if (holder == Holder.Borrowed) DeclareAll(borrowed!);
            if (holder == Holder.Foreign)
                return new($"it passes the node '{arg.Value.Syntax}', which is neither this node, a borrow nor one it created; borrow it with a Descendant, an Ancestor or a named borrow parameter instead", arg.Syntax.GetLocation(), foreign: true);
            return null;
        }

        void DeclareAll(INamedTypeSymbol type)
        {
            foreach (var name in AllComponentsOf(type)) Uses[(name, false)] = true;
        }

        (Holder, INamedTypeSymbol?) Classify(IOperation value)
        {
            switch (value)
            {
                case IInstanceReferenceOperation { ReferenceKind: InstanceReferenceKind.ContainingTypeInstance }:
                    return (Holder.Self, null);
                case IInstanceReferenceOperation { ReferenceKind: InstanceReferenceKind.ImplicitReceiver }:
                    return (Holder.Created, null);
                case IConditionalAccessInstanceOperation ci:
                    for (var up = ci.Parent; up is not null; up = up.Parent)
                        if (up is IConditionalAccessOperation ca) return Classify(ca.Operation);
                    return (Holder.Other, null);
                case IConversionOperation conversion:
                    return Classify(conversion.Operand);
                case IParenthesizedOperation parens:
                    return Classify(parens.Operand);
                case IPropertyReferenceOperation p when p.Instance is { Type: INamedTypeSymbol wrapper } && IsBorrow(wrapper)
                    && (p.Property.Name == "Node" || p.Property.Name == "Value"):
                    return (Holder.Borrowed, p.Type as INamedTypeSymbol);
                case IObjectCreationOperation:
                    return (Holder.Created, null);
                case IInvocationOperation call when IsNodeMember(call.TargetMethod) && call.TargetMethod.Name == "AddChild":
                    return (Holder.Created, null);
                case ILocalReferenceOperation local when InitializerOf(local.Local) is { } init:
                    return Classify(init);
            }
            return IsNode(value.Type) ? (Holder.Foreign, null) : (Holder.Other, null);
        }

        IOperation? InitializerOf(ILocalSymbol local)
        {
            var declarator = local.DeclaringSyntaxReferences.FirstOrDefault()?.GetSyntax() as VariableDeclaratorSyntax;
            if (declarator?.Initializer is not { } init) return null;
            return compilation.GetSemanticModel(init.SyntaxTree).GetOperation(init.Value);
        }

        Unknown? Follow(IMethodSymbol target, Location at)
        {
            if (IsNodeMember(target)) return null;
            if (target.IsVirtual || target.IsAbstract || (target.IsOverride && !target.IsSealed && !owner.IsSealed))
                return new($"it calls '{target.Name}', which a subclass may override", at);
            return Visit(target, at);
        }

        Unknown? Record(IPropertyReferenceOperation pr)
        {
            var property = pr.Property.OriginalDefinition;
            var at = pr.Syntax.GetLocation();
            var (reads, writes) = AccessOf(pr);
            var name = ComponentOf(property, owner);
            if (name is not null)
            {
                Uses[(name, true)] = (Uses.TryGetValue((name, true), out var w) && w) || writes;
                return null;
            }
            if (IsNodeMember(property))
                return writes ? new($"it writes '{property.Name}', which the scheduler cannot see", at) : null;
            if (!property.DeclaringSyntaxReferences.Any())
                return new($"it uses '{property.Name}', which is not a generated component property", at);
            if (IsAutoProperty(property)) return null;
            if (reads && property.GetMethod is { } get && Follow(get, at) is { } r) return r;
            if (writes && property.SetMethod is { } set && Follow(set, at) is { } w2) return w2;
            return null;
        }
    }

    static bool IsNode(ITypeSymbol? type)
    {
        for (var t = type as INamedTypeSymbol; t is not null; t = t.BaseType)
            if (t.Name == "Node" && t.ContainingNamespace.ToDisplayString() == "KernelEngine.Framework") return true;
        return false;
    }

    static bool IsBorrow(INamedTypeSymbol type) =>
        type.GetAttributes().Any(a => a.AttributeClass?.Name == "NodeBorrowAttribute");

    /// <summary>
    /// The expressions naming every component a node of <paramref name="type"/> carries: the
    /// native ones its <c>GeneratedNodeComponent</c> attributes name and the script slot of each
    /// type of its chain declared in source with <c>partial</c> properties.
    /// </summary>
    internal static IEnumerable<string> AllComponentsOf(INamedTypeSymbol type)
    {
        for (var t = type; t is not null; t = t.BaseType)
        {
            var markers = t.GetAttributes().Where(a => a.AttributeClass?.Name == "GeneratedNodeComponentAttribute" && a.ConstructorArguments.Length > 1).ToList();
            foreach (var m in markers) yield return $"\"{(string)m.ConstructorArguments[1].Value!}\"";
        }
        foreach (var t in ScriptSlotTypes(type))
            yield return $"global::KernelEngine.Framework.NodeTypeRegistry.Normalize(typeof({t.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat)}).FullName!)";
    }

    /// <summary>
    /// The types of <paramref name="type"/>'s chain that carry a script slot: declared in source,
    /// with no <c>GeneratedNodeComponent</c> attribute and with <c>partial</c> properties. Each
    /// has a generated <c>GeneratedRegisterComponent</c>.
    /// </summary>
    internal static IEnumerable<INamedTypeSymbol> ScriptSlotTypes(INamedTypeSymbol type)
    {
        for (var t = type; t is not null; t = t.BaseType)
        {
            if (t.GetAttributes().Any(a => a.AttributeClass?.Name == "GeneratedNodeComponentAttribute")) continue;
            if (t.GetMembers().OfType<IPropertySymbol>().Any(p => p.DeclaringSyntaxReferences.Select(r => r.GetSyntax())
                .OfType<PropertyDeclarationSyntax>().Any(d => d.Modifiers.Any(SyntaxKind.PartialKeyword))))
                yield return t;
        }
    }

    static bool IsReceiver(IInstanceReferenceOperation self) => self.Parent switch
    {
        IMemberReferenceOperation member => member.Instance == self,
        IInvocationOperation call => call.Instance == self,
        _ => false,
    };

    static (bool Reads, bool Writes) AccessOf(IPropertyReferenceOperation pr) => pr.Parent switch
    {
        ISimpleAssignmentOperation a when a.Target == pr => (false, true),
        IAssignmentOperation a when a.Target == pr => (true, true),
        IIncrementOrDecrementOperation => (true, true),
        ITupleOperation { Parent: IDeconstructionAssignmentOperation } => (false, true),
        _ => (true, false),
    };

    static bool IsNodeMember(ISymbol symbol) =>
        symbol.ContainingType is { Name: "Node" } t && t.ContainingNamespace.ToDisplayString() == "KernelEngine.Framework";

    static bool IsAutoProperty(IPropertySymbol property) =>
        property.DeclaringSyntaxReferences.Select(r => r.GetSyntax()).OfType<PropertyDeclarationSyntax>().Any(p =>
            !p.Modifiers.Any(SyntaxKind.PartialKeyword) && p.ExpressionBody is null && p.AccessorList is not null
            && p.AccessorList.Accessors.All(a => a.Body is null && a.ExpressionBody is null));

    /// <summary>
    /// The expression naming the component behind a generated property: the name a
    /// <c>GeneratedNodeComponent</c> attribute gives the struct its <c>NativeField</c> lives in,
    /// or, for a script property, the name the type's own slot is registered under. Null for any
    /// other property.
    /// </summary>
    static string? ComponentOf(IPropertySymbol property, INamedTypeSymbol owner)
    {
        var type = property.ContainingType;
        var markers = type.GetAttributes()
            .Where(a => a.AttributeClass?.Name == "GeneratedNodeComponentAttribute" && a.ConstructorArguments.Length > 1)
            .ToList();
        if (markers.Count > 0)
        {
            var field = property.GetAttributes().FirstOrDefault(a => a.AttributeClass?.Name == "NativeFieldAttribute");
            if (field is null) return null;
            var pinned = field.NamedArguments.FirstOrDefault(n => n.Key == "Component").Value.Value as INamedTypeSymbol;
            var fieldName = field.ConstructorArguments.Length > 0 ? field.ConstructorArguments[0].Value as string : null;
            var marker = pinned is not null
                ? markers.FirstOrDefault(m => SymbolEqualityComparer.Default.Equals(m.ConstructorArguments[0].Value as INamedTypeSymbol, pinned))
                : markers.Count == 1
                    ? markers[0]
                    : markers.SingleOrDefault(m => (m.ConstructorArguments[0].Value as INamedTypeSymbol)?
                        .GetMembers(fieldName ?? property.Name).OfType<IFieldSymbol>().Any() == true);
            return marker is null ? null : $"\"{(string)marker.ConstructorArguments[1].Value!}\"";
        }

        var partial = property.DeclaringSyntaxReferences.Select(r => r.GetSyntax()).OfType<PropertyDeclarationSyntax>()
            .Any(p => p.Modifiers.Any(SyntaxKind.PartialKeyword));
        if (!partial) return null;
        return SymbolEqualityComparer.Default.Equals(type, owner)
            ? "GeneratedComponentName"
            : $"global::KernelEngine.Framework.NodeTypeRegistry.Normalize(typeof({type.ToDisplayString(SymbolDisplayFormat.FullyQualifiedFormat)}).FullName!)";
    }
}
