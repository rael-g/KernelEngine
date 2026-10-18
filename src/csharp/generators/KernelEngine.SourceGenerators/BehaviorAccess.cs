using System.Collections.Generic;
using System.Linq;

using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;
using Microsoft.CodeAnalysis.Operations;

namespace KernelEngine.SourceGenerators;

/// <summary>
/// Finds the components a behavior hook reaches on its own node, by reading the operations of the
/// hook and of the methods of its class it calls. A component is one of the node's generated
/// properties, read or written through <c>this</c>. The result is null whenever the body does
/// something the reading cannot follow, and the caller then declares everything the type carries.
/// </summary>
static class BehaviorAccess
{
    /// <summary>One component the hook reaches: the expression naming it at runtime, and whether
    /// the hook writes it.</summary>
    internal sealed class Use(string nameExpression, bool writes)
    {
        public string NameExpression { get; } = nameExpression;
        public bool Writes { get; } = writes;
    }

    /// <summary>Why a hook's access could not be read, and where.</summary>
    internal sealed class Unknown(string reason, Location location)
    {
        public string Reason { get; } = reason;
        public Location Location { get; } = location;
    }

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
        return unknown is null ? walk.Uses.Select(u => new Use(u.Key, u.Value)).ToList() : null;
    }

    sealed class Walk(Compilation compilation, INamedTypeSymbol owner)
    {
        public readonly Dictionary<string, bool> Uses = new();
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
                    IPropertyReferenceOperation pr when pr.Instance is IInstanceReferenceOperation => Record(pr),
                    IInvocationOperation call when call.Instance is IInstanceReferenceOperation => Follow(call.TargetMethod, call.Syntax.GetLocation()),
                    _ => null,
                };
                if (found is not null) return found;
            }
            return null;
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
                Uses[name] = (Uses.TryGetValue(name, out var w) && w) || writes;
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
