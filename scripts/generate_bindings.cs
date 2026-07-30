#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var csharpDir = Path.Combine(rootDir, "src", "csharp");

// dotnet run compiles/caches file-based apps elsewhere, so AppContext.BaseDirectory
// does not point at this file's actual location — CallerFilePath, resolved at
// compile time against this source file, does.
static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

Console.WriteLine($"Restoring .NET tools in {csharpDir}...");
Run(["dotnet", "tool", "restore"], csharpDir);

// ClangSharpPInvokeGenerator's Linux package ships libclang.so alone, without the
// "resource dir" of builtin headers (stdbool.h, stddef.h, ...) a normal clang
// install carries alongside it — without it, parsing any header that includes
// <stdbool.h> fails with "file not found". Fetched once (matching the pinned
// clang version exactly, via the llvm-project source tree — these are the same
// plain-text headers regardless of platform) and reused across runs.
const string ClangVersion = "21.1.8";
var resourceDir = Path.Combine(rootDir, ".cache", $"clang-resource-dir-{ClangVersion}");
await EnsureClangResourceDir(resourceDir, ClangVersion);

// uint64_t/int64_t are platform-independent by the C standard's own guarantee (always
// exactly 64 bits) — but glibc happens to implement that guarantee via `unsigned long`
// (ambiguous-width in general C, though not here), while Windows' CRT uses `unsigned
// long long` (unambiguous). ClangSharp keys off which spelling was used rather than the
// typedef's actual guarantee, so it emits `nuint`/`nint` (a *genuinely* dynamic-width
// C# type) only on Linux. Remapping the two stdint.h typedefs directly makes every
// derived type (ke_entity, GPU handles, ...) and every raw field/param resolve
// identically regardless of which OS ran the generator.
var extraArgs = new[] { "-a", $"-resource-dir={resourceDir}", "-r", "uint64_t=ulong", "-r", "int64_t=long" };

// Same package also fails to resolve libclang.so itself via normal shared-library
// search paths when invoked through `dotnet tool run` — needs its own directory
// added explicitly. Windows' tool resolution doesn't have this problem.
Dictionary<string, string>? env = null;
if (!OperatingSystem.IsWindows())
{
    var nugetPackages = Environment.GetEnvironmentVariable("NUGET_PACKAGES")
        ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
    var libclangDir = Path.Combine(nugetPackages, "clangsharppinvokegenerator.linux-x64", "21.1.8.2", "tools", "any", "linux-x64");
    if (Directory.Exists(libclangDir))
    {
        var existing = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH");
        env = new Dictionary<string, string>
        {
            ["LD_LIBRARY_PATH"] = existing is null ? libclangDir : $"{libclangDir}:{existing}",
        };
    }
}

var rspFiles = Directory.EnumerateFiles(csharpDir, "*.rsp", SearchOption.AllDirectories)
    .Where(p => !p.Split(Path.DirectorySeparatorChar).Any(part => part is "bin" or "obj"))
    .ToList();

Console.WriteLine($"Found {rspFiles.Count} response files.");
var successCount = 0;

foreach (var rsp in rspFiles)
{
    Console.WriteLine($"\n--- Generating: {Path.GetRelativePath(rootDir, rsp)} ---");

    // Wipe the output dir first so bindings for types removed from the headers don't linger.
    var outDir = OutputDirFor(rsp);
    if (outDir is not null && Directory.Exists(outDir))
    {
        Console.WriteLine($"Cleaning stale bindings in {Path.GetRelativePath(rootDir, outDir)}");
        Directory.Delete(outDir, recursive: true);
    }

    string[] command = ["dotnet", "tool", "run", "ClangSharpPInvokeGenerator", $"@{rsp}", .. extraArgs];
    if (Run(command, Path.GetDirectoryName(rsp)!, env))
        successCount++;
}

Console.WriteLine($"\nDone. {successCount}/{rspFiles.Count} bindings regenerated successfully.");
return successCount == rspFiles.Count ? 0 : 1;

// ClangSharp resolves --output relative to the working directory, which is set to the
// .rsp's own folder. Multi-file codegen emits one .cs per type there, so wiping this
// directory before regenerating is what drops bindings for types removed from headers.
static string? OutputDirFor(string rsp)
{
    var rspDir = Path.GetDirectoryName(rsp)!;
    var lines = File.ReadAllLines(rsp);
    for (var i = 0; i < lines.Length; i++)
    {
        if (lines[i].Trim() == "--output" && i + 1 < lines.Length)
            return Path.GetFullPath(Path.Combine(rspDir, lines[i + 1].Trim()));
    }
    return null;
}

static async Task EnsureClangResourceDir(string resourceDir, string clangVersion)
{
    var includeDir = Path.Combine(resourceDir, "include");
    if (Directory.Exists(includeDir) && Directory.EnumerateFiles(includeDir).Any()) return;

    Console.WriteLine($"Fetching clang {clangVersion} resource-dir headers into {resourceDir}...");
    Directory.CreateDirectory(includeDir);

    using var http = new HttpClient();
    http.DefaultRequestHeaders.UserAgent.ParseAdd("KernelEngine-build-script");
    var listing = await http.GetStringAsync(
        $"https://api.github.com/repos/llvm/llvm-project/contents/clang/lib/Headers?ref=llvmorg-{clangVersion}");
    var entries = System.Text.Json.JsonDocument.Parse(listing).RootElement;

    foreach (var entry in entries.EnumerateArray())
    {
        if (entry.GetProperty("type").GetString() != "file") continue;
        var name = entry.GetProperty("name").GetString()!;
        if (!name.EndsWith(".h")) continue;
        var url = entry.GetProperty("download_url").GetString()!;
        var bytes = await http.GetByteArrayAsync(url);
        await File.WriteAllBytesAsync(Path.Combine(includeDir, name), bytes);
    }
}

static bool Run(string[] command, string cwd, Dictionary<string, string>? env = null)
{
    Console.WriteLine($"Running: {string.Join(' ', command)} in {cwd}");
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo(command[0])
        {
            WorkingDirectory = cwd,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        },
    };
    foreach (var arg in command.Skip(1)) process.StartInfo.ArgumentList.Add(arg);
    if (env is not null)
        foreach (var (k, v) in env) process.StartInfo.Environment[k] = v;
    process.Start();
    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();

    if (process.ExitCode != 0)
    {
        Console.WriteLine($"FAILED: {command[^1]}");
        Console.WriteLine($"STDOUT: {stdout}");
        Console.WriteLine($"STDERR: {stderr}");
    }
    else
    {
        Console.WriteLine($"SUCCESS: {command[^1]}");
    }
    return process.ExitCode == 0;
}
