using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace KernelEngine.Cli;

/// <summary>
/// Rewrites two things in a Program.cs from an ordered module list: the <c>using KernelEngine.</c>
/// directives, and the initializer of the <c>services</c> variable, which becomes a
/// <c>ServiceCollection</c> chain of the modules' extension calls. A missing file is created from
/// a template.
/// </summary>
public static class ProgramCsSync
{
    public static void Sync(string programCsPath, IReadOnlyList<ModuleSpec> orderedModules)
    {
        var src = File.Exists(programCsPath) ? File.ReadAllText(programCsPath) : ScaffoldTemplate();
        var tree = CSharpSyntaxTree.ParseText(src);
        var root = (CompilationUnitSyntax)tree.GetRoot();

        root = SyncUsings(root, orderedModules);
        root = SyncServicesChain(root, orderedModules);

        File.WriteAllText(programCsPath, root.NormalizeWhitespace(elasticTrivia: true).ToFullString());
    }

    private static CompilationUnitSyntax SyncUsings(CompilationUnitSyntax root, IReadOnlyList<ModuleSpec> modules)
    {
        var required = modules.Select(m => m.Using)
                              .Append("Microsoft.Extensions.DependencyInjection")
                              .Distinct(StringComparer.Ordinal)
                              .ToHashSet(StringComparer.Ordinal);

        static bool IsKernelEngine(string ns) => ns.StartsWith("KernelEngine.", StringComparison.Ordinal);

        var toRemove = root.Usings
            .Where(u => IsKernelEngine(u.Name?.ToString() ?? "") &&
                        !required.Contains(u.Name!.ToString()))
            .ToArray();
        if (toRemove.Length > 0)
            root = root.RemoveNodes(toRemove, SyntaxRemoveOptions.KeepNoTrivia)!;

        var existing = root.Usings.Select(u => u.Name?.ToString() ?? "").ToHashSet(StringComparer.Ordinal);
        var toAdd = required.Where(ns => !existing.Contains(ns))
                            .Select(ns => SyntaxFactory.UsingDirective(SyntaxFactory.ParseName(ns)))
                            .ToArray();
        if (toAdd.Length > 0)
            root = root.AddUsings(toAdd);

        return root;
    }

    private static CompilationUnitSyntax SyncServicesChain(CompilationUnitSyntax root, IReadOnlyList<ModuleSpec> modules)
    {
        var initializer = root.DescendantNodes()
            .OfType<LocalDeclarationStatementSyntax>()
            .FirstOrDefault(d => d.Declaration.Variables.Any(v => v.Identifier.Text == "services"
                                                                  && v.Initializer != null));

        var chainExpr = BuildChain(modules);

        if (initializer is null)
        {
            var declStmt = SyntaxFactory.ParseStatement($"var services = {chainExpr};")
                                          .WithLeadingTrivia(SyntaxFactory.LineFeed);
            return root.WithMembers(root.Members.Insert(0, SyntaxFactory.GlobalStatement(declStmt)));
        }

        var newInitializer = SyntaxFactory.EqualsValueClause(SyntaxFactory.ParseExpression(chainExpr));
        var oldVar = initializer.Declaration.Variables.First(v => v.Identifier.Text == "services");
        var newVar = oldVar.WithInitializer(newInitializer);
        var newDecl = initializer.Declaration.ReplaceNode(oldVar, newVar);
        return root.ReplaceNode(initializer, initializer.WithDeclaration(newDecl));
    }

    private static string BuildChain(IReadOnlyList<ModuleSpec> modules)
    {
        if (modules.Count == 0) return "new ServiceCollection()";
        var calls = string.Join(Environment.NewLine + "    ",
            modules.Select(m => $".{m.Extension}()"));
        return "new ServiceCollection()" + Environment.NewLine + "    " + calls;
    }

    internal static string ScaffoldTemplate() => """
        using Microsoft.Extensions.DependencyInjection;

        var services = new ServiceCollection();

        """;
}
