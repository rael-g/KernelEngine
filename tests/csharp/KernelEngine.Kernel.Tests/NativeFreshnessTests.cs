using System.IO;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using Xunit;

namespace EngineTests;

/// <summary>
/// Fails when a contract or factory header changed after the native libraries were built.
/// </summary>
public class NativeFreshnessTests
{
    private const string StampHeader = "ke-abi-stamp 1";

    [Fact]
    public void NativeLibraries_WereBuiltFromTheHeadersOnDisk()
    {
        var root = FindRepoRoot();
        var prefix = typeof(NativeFreshnessTests).Assembly
            .GetCustomAttributes<AssemblyMetadataAttribute>()
            .Single(a => a.Key == "NativePrefix").Value!
            .Replace('\\', '/').TrimEnd('/');
        var stamp = Path.Combine([root, .. prefix.Split('/'), "abi.stamp"]);
        Assert.True(File.Exists(stamp),
            $"{stamp} does not exist: build the native side first with `zig build --prefix build/native --cache-dir build/zig-cache`");

        var stale = Compare(root, File.ReadAllLines(stamp));

        Assert.True(stale.Count == 0,
            "native libraries are older than these headers; rebuild with `zig build --prefix build/native --cache-dir build/zig-cache`:\n  "
            + string.Join("\n  ", stale));
    }

    [Fact]
    public void Compare_FlagsAChangedHeaderAndAMissingOne_AndPassesAnUnchangedOne()
    {
        var dir = Directory.CreateTempSubdirectory("abi_fresh_").FullName;
        try
        {
            Directory.CreateDirectory(Path.Combine(dir, "src", "c"));
            File.WriteAllText(Path.Combine(dir, "src", "c", "kept.h"), "int kept;\r\n");
            File.WriteAllText(Path.Combine(dir, "src", "c", "edited.h"), "int before;\n");
            var lines = new[]
            {
                StampHeader,
                $"{Digest("int kept;\n")}  src/c/kept.h",
                $"{Digest("int before;\n")}  src/c/edited.h",
                $"{Digest("int gone;\n")}  src/c/removed.h",
            };
            File.WriteAllText(Path.Combine(dir, "src", "c", "edited.h"), "int after;\n");

            var stale = Compare(dir, lines);

            Assert.Equal(["src/c/edited.h", "src/c/removed.h"], stale.OrderBy(s => s, System.StringComparer.Ordinal));
        }
        finally
        {
            Directory.Delete(dir, recursive: true);
        }
    }

    [Fact]
    public void Compare_RefusesAStampItDoesNotRecognise()
    {
        var stale = Compare(Path.GetTempPath(), ["something else", "00  src/c/a.h"]);
        Assert.Contains(stale, s => s.Contains("unrecognised"));
    }

    private static System.Collections.Generic.List<string> Compare(string root, string[] stampLines)
    {
        var stale = new System.Collections.Generic.List<string>();
        if (stampLines.Length == 0 || stampLines[0] != StampHeader)
        {
            stale.Add("abi.stamp has an unrecognised format");
            return stale;
        }

        foreach (var line in stampLines.Skip(1).Where(l => l.Length > 0))
        {
            var split = line.IndexOf("  ", System.StringComparison.Ordinal);
            var recorded = line[..split];
            var rel = line[(split + 2)..];
            var path = Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(path) || Digest(File.ReadAllBytes(path)) != recorded)
                stale.Add(rel);
        }
        return stale;
    }

    private static string Digest(string text) => Digest(System.Text.Encoding.UTF8.GetBytes(text));

    private static string Digest(byte[] bytes) =>
        Convert.ToHexString(SHA256.HashData(bytes.Where(b => b != (byte)'\r').ToArray())).ToLowerInvariant();

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
