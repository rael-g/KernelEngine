#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var csharpDir = Path.Combine(rootDir, "src", "csharp");
var check = args.Contains("--check");
var checkRoot = Path.Combine(Path.GetTempPath(), "ke_bindings_check_" + Guid.NewGuid().ToString("N")[..8]);

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

Console.WriteLine($"Restoring .NET tools in {csharpDir}...");
Run(["dotnet", "tool", "restore"], csharpDir);

const string ClangVersion = "21.1.8";
var resourceDir = Path.Combine(rootDir, "build", "cache", $"clang-resource-dir-{ClangVersion}");
await EnsureClangResourceDir(resourceDir, ClangVersion);

var extraArgs = new[] { "-a", $"-resource-dir={resourceDir}", "-r", "uint64_t=ulong", "-r", "int64_t=long" };

Dictionary<string, string>? env = null;
string[] generator = ["dotnet", "tool", "run", "ClangSharpPInvokeGenerator"];
if (!OperatingSystem.IsWindows())
{
    var nugetPackages = Environment.GetEnvironmentVariable("NUGET_PACKAGES") ?? GlobalPackagesFolder(csharpDir);
    var libclangDir = Path.Combine(nugetPackages, "clangsharppinvokegenerator.linux-x64", "21.1.8.2", "tools", "any", "linux-x64");
    if (Directory.Exists(libclangDir))
    {
        var executable = Path.Combine(libclangDir, "ClangSharpPInvokeGenerator");
        if (File.Exists(executable)) generator = [executable];
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

var drift = new List<string>();
var failed = 0;

try
{
    foreach (var rsp in rspFiles)
    {
        var name = Path.GetRelativePath(rootDir, rsp);
        var committedDir = OutputDirFor(rsp);

        if (check)
        {
            var target = Path.Combine(checkRoot, Path.GetFileNameWithoutExtension(rsp));
            var probe = Path.Combine(Path.GetDirectoryName(rsp)!, Path.GetFileNameWithoutExtension(rsp) + ".check.rsp");
            try
            {
                File.WriteAllText(probe, WithOutput(File.ReadAllLines(rsp), target));
                string[] checkCommand = [.. generator, $"@{probe}", .. extraArgs];
                Run(checkCommand, Path.GetDirectoryName(rsp)!, env, quiet: true);
            }
            finally
            {
                File.Delete(probe);
            }

            if (!Directory.Exists(target) || !Directory.EnumerateFiles(target, "*.cs", SearchOption.AllDirectories).Any())
            {
                Console.WriteLine($"[?] {name}: the generator wrote nothing, so nothing was compared");
                failed++;
            }
            else if (committedDir is null || !Directory.Exists(committedDir))
            {
                Console.WriteLine($"[DRIFT] {name}: the committed output directory is missing");
                drift.Add(name);
            }
            else if (!SameTree(target, committedDir))
            {
                Console.WriteLine($"[DRIFT] {name}: the committed bindings differ from what the headers generate");
                drift.Add(name);
            }
            continue;
        }

        Console.WriteLine($"\n--- Generating: {name} ---");

        string? previousDir = null;
        if (committedDir is not null && Directory.Exists(committedDir))
        {
            Console.WriteLine($"Replacing the bindings in {Path.GetRelativePath(rootDir, committedDir)}");
            previousDir = committedDir.TrimEnd(Path.DirectorySeparatorChar) + ".previous";
            if (Directory.Exists(previousDir)) Directory.Delete(previousDir, recursive: true);
            Directory.Move(committedDir, previousDir);
        }

        string[] command = [.. generator, $"@{rsp}", .. extraArgs];
        int exitCode;
        string stdout, stderr;
        try
        {
            (exitCode, stdout, stderr) = Run(command, Path.GetDirectoryName(rsp)!, env);
        }
        catch
        {
            RestorePrevious(committedDir, previousDir);
            throw;
        }

        var wrote = committedDir is not null && Directory.Exists(committedDir)
            && Directory.EnumerateFiles(committedDir, "*.cs", SearchOption.AllDirectories).Any();

        if (wrote)
        {
            if (previousDir is not null) Directory.Delete(previousDir, recursive: true);
            successCount++;
            if (exitCode != 0) Console.WriteLine($"WARNINGS: {name} (bindings written)");
        }
        else
        {
            RestorePrevious(committedDir, previousDir);
            Console.WriteLine($"FAILED: {name} wrote no bindings; the previous bindings were kept");
            Console.WriteLine($"STDOUT: {stdout}");
            Console.WriteLine($"STDERR: {stderr}");
        }
    }
}
finally
{
    if (Directory.Exists(checkRoot)) Directory.Delete(checkRoot, recursive: true);
}

if (check)
{
    if (drift.Count > 0)
    {
        Console.WriteLine("\n[FAIL] Drift detected! Please run 'dotnet run scripts/generate_bindings.cs' and commit the changes.");
        return 1;
    }
    if (failed > 0)
    {
        Console.WriteLine("\nThe check could not run to completion; it says nothing about drift.");
        return 2;
    }
    Console.WriteLine($"[OK] All {rspFiles.Count} bindings are up to date.");
    return 0;
}

Console.WriteLine($"\nDone. {successCount}/{rspFiles.Count} bindings regenerated successfully.");
return successCount == rspFiles.Count ? 0 : 1;

static void RestorePrevious(string? committedDir, string? previousDir)
{
    if (committedDir is null || previousDir is null) return;
    if (Directory.Exists(committedDir)) Directory.Delete(committedDir, recursive: true);
    Directory.Move(previousDir, committedDir);
}

static string WithOutput(string[] lines, string outputDir)
{
    var copy = (string[])lines.Clone();
    for (var i = 0; i < copy.Length - 1; i++)
        if (copy[i].Trim() == "--output") copy[i + 1] = outputDir;
    return string.Join('\n', copy) + "\n";
}

static bool SameTree(string a, string b)
{
    var left = Directory.EnumerateFiles(a, "*", SearchOption.AllDirectories)
        .Select(f => Path.GetRelativePath(a, f)).Order().ToList();
    var right = Directory.EnumerateFiles(b, "*", SearchOption.AllDirectories)
        .Select(f => Path.GetRelativePath(b, f)).Order().ToList();
    return left.SequenceEqual(right)
        && left.All(rel => File.ReadAllBytes(Path.Combine(a, rel)).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(b, rel))));
}

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

static string GlobalPackagesFolder(string workingDirectory)
{
    var result = Run(["dotnet", "nuget", "locals", "global-packages", "--list"], workingDirectory, quiet: true);
    const string Prefix = "global-packages:";
    foreach (var line in result.Stdout.Split('\n'))
        if (line.Trim() is var trimmed && trimmed.StartsWith(Prefix, StringComparison.Ordinal))
            return trimmed[Prefix.Length..].Trim();
    return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".nuget", "packages");
}

static (int ExitCode, string Stdout, string Stderr) Run(string[] command, string cwd, Dictionary<string, string>? env = null, bool quiet = false)
{
    if (!quiet) Console.WriteLine($"Running: {string.Join(' ', command)} in {cwd}");
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

    return (process.ExitCode, stdout, stderr);
}
