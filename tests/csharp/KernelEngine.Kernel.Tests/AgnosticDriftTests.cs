using System.IO;
using System.Linq;
using System.Collections.Generic;
using Xunit;
using Xunit.Abstractions;

namespace EngineTests;

/// <summary>
/// Structural test: no backend-specific symbol may leak into the layers that are meant to be
/// agnostic of the graphics backend. A layer that cannot be found, or that yields no file to
/// read, fails the test: a scan that opens nothing proves nothing.
/// </summary>
public class AgnosticDriftTests(ITestOutputHelper output)
{
    private static readonly string[] ForbiddenSymbols =
        ["bgfx::", "Vulkan", "Direct3D", "d3d", "glsl", "vulkan"];

    private static readonly string[] SkippedSubdirs = ["bin", "obj", "Generated"];

    private static IEnumerable<(string RelPath, string[] Extensions)> AgnosticLayers(string root)
    {
        yield return ("src/c", [".h"]);
        yield return ("src/csharp/framework", [".cs"]);
        foreach (var dir in Directory.EnumerateDirectories(Path.Combine(root, "src", "csharp"), "*.Abstractions", SearchOption.AllDirectories))
            yield return (Path.GetRelativePath(root, dir).Replace(Path.DirectorySeparatorChar, '/'), [".cs"]);
    }

    [Fact]
    public void AgnosticLayers_ContainNoBackendSpecificSymbols()
    {
        var root = FindRepoRoot();
        var violations = new List<string>();
        var filesRead = 0;

        foreach (var (relPath, extensions) in AgnosticLayers(root))
        {
            var dir = Path.Combine(root, relPath.Replace('/', Path.DirectorySeparatorChar));
            Assert.True(Directory.Exists(dir), $"agnostic layer '{relPath}' does not exist, so nothing in it was checked");
            filesRead += Scan(dir, extensions, root, violations);
        }

        foreach (var v in violations)
            output.WriteLine(v);

        Assert.True(filesRead > 0, "the scan opened no file");
        Assert.Empty(violations);
    }

    [Fact]
    public void Scanner_FlagsAForbiddenSymbolInCode_AndIgnoresItInComments()
    {
        var dir = Directory.CreateTempSubdirectory("agnostic_scan_").FullName;
        try
        {
            File.WriteAllText(Path.Combine(dir, "leak.h"), "int Vulkan_handle;\n// Vulkan is only named in a comment\n");
            var violations = new List<string>();

            var read = Scan(dir, [".h"], dir, violations);

            Assert.Equal(1, read);
            var only = Assert.Single(violations);
            Assert.StartsWith("leak.h:1:", only);
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    private static int Scan(string dir, string[] extensions, string root, List<string> violations)
    {
        var files = Directory
            .EnumerateFiles(dir, "*.*", SearchOption.AllDirectories)
            .Where(f => extensions.Contains(Path.GetExtension(f)))
            .Where(f => !PathContainsSkippedDir(f, dir))
            .ToList();

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
        return files.Count;
    }

    private static bool PathContainsSkippedDir(string path, string scannedDir)
    {
        var parts = Path.GetRelativePath(scannedDir, path).Split(Path.DirectorySeparatorChar, System.StringSplitOptions.RemoveEmptyEntries);
        return parts.Any(p => SkippedSubdirs.Contains(p, System.StringComparer.OrdinalIgnoreCase));
    }

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
            var git = Path.Combine(dir.FullName, ".git");
            if (Directory.Exists(git) || File.Exists(git))
                return dir.FullName;
            dir = dir.Parent;
        }
        throw new System.InvalidOperationException(
            $"Cannot locate repository root from {AppContext.BaseDirectory}");
    }
}
