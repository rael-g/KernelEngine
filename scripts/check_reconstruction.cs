#!/usr/bin/env dotnet run

// Regenerates every kabic-owned artifact into a throwaway root and compares it with
// the one in the tree. This is the gate the drift checks cannot be: they ask whether
// the committed output matches the current headers, which a hand edit that happens to
// agree would also pass. This asks the harder question — can the command produce the
// tree from nothing — and a file the command no longer knows how to make shows up as
// missing rather than as silence.

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

var zigOverride = args.Length > 1 && args[0] == "--zig" ? args[1] : null;

var shadow = Path.Combine(Path.GetTempPath(), "ke-reconstruction-" + Guid.NewGuid().ToString("N")[..8]);
Console.WriteLine("Rebuilding every generated artifact from the headers alone...");

try
{
    var regenArgs = new List<string> { "run", "--project", Path.Combine(rootDir, "src", "csharp", "kabic", "Kabic.Cli"),
        "--", "generate", "--into", shadow };
    if (zigOverride is not null) regenArgs.AddRange(["--zig", zigOverride]);

    if (!Run(regenArgs, out var err))
    {
        Console.Error.WriteLine($"[!] regeneration failed:\n{err}");
        return 1;
    }

    var differing = new List<string>();
    var missing = new List<string>();
    var produced = 0;

    foreach (var made in Directory.EnumerateFiles(shadow, "*", SearchOption.AllDirectories))
    {
        produced++;
        var relative = Path.GetRelativePath(shadow, made);
        var committed = Path.Combine(rootDir, relative);
        if (!File.Exists(committed)) { missing.Add(relative); continue; }
        if (!File.ReadAllBytes(made).AsSpan().SequenceEqual(File.ReadAllBytes(committed)))
            differing.Add(relative);
    }

    foreach (var m in missing) Console.Error.WriteLine($"  produced but absent from the tree: {m}");
    foreach (var d in differing) Console.Error.WriteLine($"  differs from what the headers produce: {d}");

    if (missing.Count > 0 || differing.Count > 0)
    {
        Console.Error.WriteLine(
            $"\n{missing.Count + differing.Count} of {produced} artifact(s) do not match a clean rebuild.\n"
            + "Run 'dotnet run --project src/csharp/kabic/Kabic.Cli -- generate' and commit the result.");
        return 1;
    }

    Console.WriteLine($"All {produced} generated artifact(s) rebuild identically from the headers.");
    return 0;
}
finally
{
    if (Directory.Exists(shadow)) Directory.Delete(shadow, recursive: true);
}

bool Run(List<string> arguments, out string error)
{
    var psi = new ProcessStartInfo("dotnet") { WorkingDirectory = rootDir, RedirectStandardError = true, RedirectStandardOutput = true };
    foreach (var a in arguments) psi.ArgumentList.Add(a);
    using var p = Process.Start(psi)!;
    var stderr = p.StandardError.ReadToEnd();
    p.StandardOutput.ReadToEnd();
    p.WaitForExit();
    error = stderr;
    return p.ExitCode == 0;
}
