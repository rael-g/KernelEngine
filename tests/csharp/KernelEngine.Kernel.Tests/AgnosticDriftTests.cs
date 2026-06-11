using System.IO;
using System.Linq;
using System.Collections.Generic;
using Xunit;
using Xunit.Abstractions;

namespace KernelEngine.Kernel.Tests;

/// <summary>
/// D.1 structural test: verifies that no backend-specific symbol has leaked into the
/// agnostic kernel/framework layers. Runs on every build; zero matches = pass.
/// </summary>
public class AgnosticDriftTests(ITestOutputHelper output)
{
    // Symbols that must never appear in agnostic source code (not in comments).
    private static readonly string[] ForbiddenSymbols =
        ["bgfx::", "Vulkan", "Direct3D", "d3d", "glsl", "vulkan"];

    // Directories (repo-relative, forward slashes) and file extensions to scan.
    private static readonly (string RelPath, string[] Extensions)[] ScannedDirs =
    [
        ("src/c/kernel",                         [".h", ".c"]),
        ("src/csharp/KernelEngine.Kernel",        [".cs"]),
        ("src/csharp/KernelEngine.Kernel.Abstractions", [".cs"]),
        ("src/csharp/KernelEngine.Framework.Legacy",     [".cs"]),
    ];

    // Subdirectory names that are always skipped (generated/build output).
    private static readonly string[] SkippedSubdirs = ["bin", "obj", "Generated"];

    [Fact]
    public void AgnosticLayers_ContainNoBackendSpecificSymbols()
    {
        var root = FindRepoRoot();
        var violations = new List<string>();

        foreach (var (relPath, extensions) in ScannedDirs)
        {
            var dir = Path.Combine(root, relPath.Replace('/', Path.DirectorySeparatorChar));
            if (!Directory.Exists(dir))
                continue;

            var files = Directory
                .EnumerateFiles(dir, "*.*", SearchOption.AllDirectories)
                .Where(f => extensions.Contains(Path.GetExtension(f)))
                .Where(f => !PathContainsSkippedDir(f));

            foreach (var file in files)
            {
                var lines = File.ReadAllLines(file);
                for (int i = 0; i < lines.Length; i++)
                {
                    var code = CodePortion(lines[i]);
                    if (code.Length == 0)
                        continue;

                    foreach (var symbol in ForbiddenSymbols)
                    {
                        if (code.Contains(symbol, StringComparison.Ordinal))
                            violations.Add($"{Path.GetRelativePath(root, file)}:{i + 1}: {lines[i].Trim()}");
                    }
                }
            }
        }

        foreach (var v in violations)
            output.WriteLine(v);

        Assert.Empty(violations);
    }

    private static bool PathContainsSkippedDir(string path)
    {
        var parts = path.Split(Path.DirectorySeparatorChar, System.StringSplitOptions.RemoveEmptyEntries);
        return parts.Any(p => SkippedSubdirs.Contains(p, System.StringComparer.OrdinalIgnoreCase));
    }

    // Returns the code portion of a line, stripping single-line and trailing inline comments.
    // Handles whole-line comments (//…, ///…, *…, /*…) and trailing inline // comments.
    // Note: does not handle // inside string literals, which do not appear in these source layers.
    private static string CodePortion(string line)
    {
        var t = line.TrimStart();
        if (t.StartsWith("//") || t.StartsWith("*") || t.StartsWith("/*"))
            return string.Empty;

        var idx = line.IndexOf("//", StringComparison.Ordinal);
        return idx >= 0 ? line[..idx] : line;
    }

    private static string FindRepoRoot()
    {
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir is not null)
        {
            if (Directory.Exists(Path.Combine(dir.FullName, ".git")))
                return dir.FullName;
            dir = dir.Parent;
        }
        throw new System.InvalidOperationException(
            $"Cannot locate repository root from {AppContext.BaseDirectory}");
    }
}
