using System.Text.Json;

namespace Kabic.Bindings;

/// <summary>
/// Provides the clang resource-directory headers that ClangSharp is run with, fetching them once
/// into the cache folder under the root directory.
/// </summary>
public static class ClangResourceDir
{
    /// <summary>
    /// The clang release whose resource-directory headers are fetched.
    /// </summary>
    public const string ClangVersion = "21.1.8";

    /// <summary>
    /// Returns the resource directory under <paramref name="rootDir"/>, downloading its headers
    /// first when the include folder has none.
    /// </summary>
    public static async Task<string> EnsureAsync(string rootDir)
    {
        var resourceDir = Path.Combine(rootDir, "build", "cache", $"clang-resource-dir-{ClangVersion}");
        var includeDir = Path.Combine(resourceDir, "include");
        if (Directory.Exists(includeDir) && Directory.EnumerateFiles(includeDir).Any()) return resourceDir;

        Console.WriteLine($"Fetching clang {ClangVersion} resource-dir headers into {resourceDir}...");
        Directory.CreateDirectory(includeDir);

        using var http = new HttpClient();
        http.DefaultRequestHeaders.UserAgent.ParseAdd("kabic");
        var listing = await http.GetStringAsync(
            $"https://api.github.com/repos/llvm/llvm-project/contents/clang/lib/Headers?ref=llvmorg-{ClangVersion}");
        foreach (var entry in JsonDocument.Parse(listing).RootElement.EnumerateArray())
        {
            if (entry.GetProperty("type").GetString() != "file") continue;
            var name = entry.GetProperty("name").GetString()!;
            if (!name.EndsWith(".h")) continue;
            var bytes = await http.GetByteArrayAsync(entry.GetProperty("download_url").GetString()!);
            await File.WriteAllBytesAsync(Path.Combine(includeDir, name), bytes);
        }
        return resourceDir;
    }
}
