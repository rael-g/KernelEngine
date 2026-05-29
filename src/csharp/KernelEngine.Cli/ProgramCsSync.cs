using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;
using Microsoft.CodeAnalysis.CSharp.Syntax;

namespace KernelEngine.Cli;

/// <summary>
/// Surgically rewrites the bootstrap chain in a Program.cs given the desired module set
/// (topologically ordered). Two responsibilities:
///   1. The <c>using KernelEngine.…;</c> directives every active module needs.
///   2. The <c>var services = new ServiceCollection().Add…()…;</c> chain on top of which the
///      app is built.
///
/// Everything else in Program.cs (the user's <c>OnReady</c> lambdas, custom service
/// registrations, helper classes) is preserved verbatim. If Program.cs doesn't exist yet,
/// a minimal template is scaffolded.
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

    // ── usings ──────────────────────────────────────────────────────────────

    private static CompilationUnitSyntax SyncUsings(CompilationUnitSyntax root, IReadOnlyList<ModuleSpec> modules)
    {
        // What the manifest's modules need, plus the always-required DI extension namespace.
        var required = modules.Select(m => m.Using)
                              .Append("Microsoft.Extensions.DependencyInjection")
                              .Distinct(StringComparer.Ordinal)
                              .ToHashSet(StringComparer.Ordinal);

        // We only manage `KernelEngine.*` usings — anything else (System.*, Microsoft.*, the user's
        // own helper namespaces) is left untouched so user-authored code keeps compiling.
        static bool IsKernelEngine(string ns) => ns.StartsWith("KernelEngine.", StringComparison.Ordinal);

        // Drop KernelEngine.* usings that are no longer needed.
        var toRemove = root.Usings
            .Where(u => IsKernelEngine(u.Name?.ToString() ?? "") &&
                        !required.Contains(u.Name!.ToString()))
            .ToArray();
        if (toRemove.Length > 0)
            root = root.RemoveNodes(toRemove, SyntaxRemoveOptions.KeepNoTrivia)!;

        // Add missing required ones.
        var existing = root.Usings.Select(u => u.Name?.ToString() ?? "").ToHashSet(StringComparer.Ordinal);
        var toAdd = required.Where(ns => !existing.Contains(ns))
                            .Select(ns => SyntaxFactory.UsingDirective(SyntaxFactory.ParseName(ns)))
                            .ToArray();
        if (toAdd.Length > 0)
            root = root.AddUsings(toAdd);

        return root;
    }

    // ── services chain ──────────────────────────────────────────────────────

    private static CompilationUnitSyntax SyncServicesChain(CompilationUnitSyntax root, IReadOnlyList<ModuleSpec> modules)
    {
        // Find the top-level statement that initializes `services` from a `new ServiceCollection()`
        // chain. The most common shape is `var services = new ServiceCollection()....;`.
        var initializer = root.DescendantNodes()
            .OfType<LocalDeclarationStatementSyntax>()
            .FirstOrDefault(d => d.Declaration.Variables.Any(v => v.Identifier.Text == "services"
                                                                  && v.Initializer != null));

        var chainExpr = BuildChain(modules);

        if (initializer is null)
        {
            // No existing services declaration — inject one at the start of the global statements.
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

    // ── template ────────────────────────────────────────────────────────────

    private static string ScaffoldTemplate() => """
        using KernelEngine.Framework;
        using Microsoft.Extensions.DependencyInjection;

        var services = new ServiceCollection();

        using var app = new Application();
        app.Run(services);
        """;
}
