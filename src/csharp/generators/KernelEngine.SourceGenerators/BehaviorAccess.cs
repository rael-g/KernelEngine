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

    /// <summary>
    /// The components <paramref name="hook"/>, declared on <paramref name="owner"/>, reaches on its
    /// own node, or null when its body cannot be followed: <c>this</c> used other than as the
    /// receiver of a member, a call on <c>this</c> to a method with no source or one a subclass
    /// may override, or a property of the node that is neither generated nor plain state.
    /// </summary>
    internal static List<Use>? Analyze(Compilation compilation, INamedTypeSymbol owner, IMethodSymbol hook)
    {
        var uses = new Dictionary<string, bool>();
        var visited = new HashSet<IMethodSymbol>(SymbolEqualityComparer.Default);
        if (!Visit(compilation, owner, hook, uses, visited)) return null;
        return uses.Select(u => new Use(u.Key, u.Value)).ToList();
    }

    static bool Visit(Compilation compilation, INamedTypeSymbol owner, IMethodSymbol method,
        Dictionary<string, bool> uses, HashSet<IMethodSymbol> visited)
    {
        if (!visited.Add(method.OriginalDefinition)) return true;
        var syntax = method.DeclaringSyntaxReferences.FirstOrDefault()?.GetSyntax();
        if (syntax is null) return false;
        var operation = compilation.GetSemanticModel(syntax.SyntaxTree).GetOperation(syntax);
        if (operation is null) return false;

        foreach (var op in operation.DescendantsAndSelf())
        {
            switch (op)
            {
                case IInstanceReferenceOperation self when self.ReferenceKind == InstanceReferenceKind.ContainingTypeInstance:
                    if (!IsReceiver(self)) return false;
                    break;
                case IPropertyReferenceOperation pr when pr.Instance is IInstanceReferenceOperation:
                    if (!Record(compilation, owner, pr, uses, visited)) return false;
                    break;
                case IInvocationOperation call when call.Instance is IInstanceReferenceOperation:
                    if (!Follow(compilation, owner, call.TargetMethod, uses, visited)) return false;
                    break;
            }
        }
        return true;
    }

    static bool IsReceiver(IInstanceReferenceOperation self) => self.Parent switch
    {
        IMemberReferenceOperation member => member.Instance == self,
        IInvocationOperation call => call.Instance == self,
        _ => false,
    };

    static bool Follow(Compilation compilation, INamedTypeSymbol owner, IMethodSymbol target,
        Dictionary<string, bool> uses, HashSet<IMethodSymbol> visited)
    {
        if (IsNodeMember(target)) return true;
        if (target.IsVirtual || target.IsAbstract || (target.IsOverride && !target.IsSealed && !owner.IsSealed))
            return false;
        return Visit(compilation, owner, target, uses, visited);
    }

    static bool Record(Compilation compilation, INamedTypeSymbol owner, IPropertyReferenceOperation pr,
        Dictionary<string, bool> uses, HashSet<IMethodSymbol> visited)
    {
        var property = pr.Property.OriginalDefinition;
        var (reads, writes) = AccessOf(pr);
        var name = ComponentOf(property, owner);
        if (name is not null)
        {
            uses[name] = (uses.TryGetValue(name, out var w) && w) || writes;
            return true;
        }
        if (IsNodeMember(property)) return !writes;
        if (!property.DeclaringSyntaxReferences.Any()) return false;
        if (IsAutoProperty(property)) return true;
        if (reads && property.GetMethod is { } get && !Follow(compilation, owner, get, uses, visited)) return false;
        if (writes && property.SetMethod is { } set && !Follow(compilation, owner, set, uses, visited)) return false;
        return true;
    }

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
