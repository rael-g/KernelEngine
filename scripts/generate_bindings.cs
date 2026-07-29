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

    if (Run(["dotnet", "tool", "run", "ClangSharpPInvokeGenerator", $"@{rsp}"], Path.GetDirectoryName(rsp)!))
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

static bool Run(string[] command, string cwd)
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
