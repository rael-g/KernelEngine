#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var nativeArgs = new[] { "--prefix", "build/native", "--cache-dir", "build/zig-cache" };

var stages = new Dictionary<string, Func<List<Step>>>
{
    ["build"] = () => [new Step("zig build", "zig", ["build", .. nativeArgs])],
    ["test-native"] = () => [new Step("zig build test", "zig", ["build", "test", .. nativeArgs])],
    ["test-managed"] = () => [new Step("dotnet test", "dotnet", ["test", "KernelEngine.slnx"])],
    ["gates"] = Gates,
};
string[] order = ["build", "test-native", "test-managed", "gates"];

var selected = args.Where(a => !a.StartsWith("--")).ToList();
if (selected.Count == 0 || selected.Contains("all")) selected = [.. order];
var unknown = selected.Where(s => !stages.ContainsKey(s)).ToList();
if (unknown.Count > 0)
{
    Console.Error.WriteLine($"unknown stage '{unknown[0]}'; stages: {string.Join(", ", order)}, all");
    return 2;
}
var keepGoing = args.Contains("--keep-going");

var results = new List<(string Name, double Seconds, int Exit)>();
foreach (var stage in order.Where(selected.Contains))
{
    foreach (var step in stages[stage]())
    {
        Console.WriteLine($"--- {step.Name}");
        var started = Stopwatch.StartNew();
        var exit = Run(step);
        results.Add((step.Name, started.Elapsed.TotalSeconds, exit));
        if (exit != 0 && !keepGoing && stage != "gates") goto done;
    }
}

done:
Console.WriteLine();
foreach (var (name, seconds, exit) in results)
    Console.WriteLine($"{(exit == 0 ? "ok  " : "FAIL")} {name,-40} {seconds,7:F1}s");
Console.WriteLine($"{"",5}{"total",-40} {results.Sum(r => r.Seconds),7:F1}s");
return results.Any(r => r.Exit != 0) ? 1 : 0;

List<Step> Gates() =>
    Directory.EnumerateFiles(Path.Combine(rootDir, "scripts"), "check_*.cs").Order()
        .Select(f => new Step(Path.GetFileName(f), "dotnet",
            Path.GetFileName(f) is "check_generator_shapes.cs" or "check_zig_shapes.cs"
                ? ["run", "--no-cache", f] : ["run", f]))
        .ToList();

int Run(Step step)
{
    var info = new ProcessStartInfo(step.Command) { WorkingDirectory = rootDir };
    foreach (var a in step.Args) info.ArgumentList.Add(a);
    var lib = Path.Combine(rootDir, "build", "native", "lib");
    var existing = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH");
    info.Environment["LD_LIBRARY_PATH"] = string.IsNullOrEmpty(existing) ? lib : $"{lib}:{existing}";
    using var process = Process.Start(info)!;
    process.WaitForExit();
    return process.ExitCode;
}

record Step(string Name, string Command, string[] Args);
