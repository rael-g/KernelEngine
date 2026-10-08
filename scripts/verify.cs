#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var nativeArgs = new[] { "--prefix", "build/native", "--cache-dir", "build/zig-cache", "--global-cache-dir", "build/zig-global" };

var stages = new Dictionary<string, Func<List<Step>>>
{
    ["build"] = () => [new Step("zig build", "zig", ["build", "--summary", "all", .. nativeArgs])],
    ["test-native"] = () => [new Step("zig build test", "zig", ["build", "test", .. nativeArgs])],
    ["test-managed"] = () => [new Step("dotnet test", "dotnet", ["test", "KernelEngine.slnx"])],
    ["test-windows"] = () => [new Step("zig build test windows", "zig", ["build", "test", "-Dtarget=x86_64-windows-gnu", "-fwine", "--prefix", "build/cross-windows", "--cache-dir", "build/zig-cache-win", "--global-cache-dir", "build/zig-global"])],
    ["test-managed-windows"] = ManagedWindowsTests,
    ["gates"] = Gates,
    ["visual"] = () => [new Step("visual", "dotnet", ["run", "scripts/visual.cs", .. args.Where(a => a == "--update")])],
    ["cross-windows"] = () => [new Step("zig build windows", "zig", ["build", "-Dtarget=x86_64-windows-gnu", "--prefix", "build/cross-windows", "--cache-dir", "build/zig-cache-win", "--global-cache-dir", "build/zig-global"])],
};
string[] order = ["build", "test-native", "test-managed", "gates", "visual", "cross-windows", "test-windows", "test-managed-windows"];

var selected = args.Where(a => !a.StartsWith("--")).ToList();
if (selected.Count == 0 || selected.Contains("all")) selected = [.. order.Where(s => s is not ("cross-windows" or "test-windows" or "test-managed-windows"))];
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

List<Step> ManagedWindowsTests()
{
    var windowsDotnet = Environment.GetEnvironmentVariable("DOTNET_WINDOWS_ROOT");
    if (string.IsNullOrEmpty(windowsDotnet))
        return [new Step("test-managed-windows needs DOTNET_WINDOWS_ROOT, the Windows .NET SDK the wine ci image carries", "false", [])];
    var prefix = Path.Combine(rootDir, "build", "cross-windows");
    var artifacts = Path.Combine(rootDir, "build", "artifacts-windows");
    var steps = new List<Step>();
    foreach (var project in Directory.EnumerateFiles(Path.Combine(rootDir, "tests", "csharp"), "*.csproj", SearchOption.AllDirectories).Order())
    {
        var name = Path.GetFileNameWithoutExtension(project);
        var assembly = Path.Combine(artifacts, "bin", name, "debug", name + ".dll");
        steps.Add(new Step($"dotnet build {name} for windows", "dotnet",
            ["build", project, "-p:NativeOS=win", $"-p:NativePrefix={prefix}", $"-p:ArtifactsPath={artifacts}"]));
        steps.Add(new Step($"dotnet test {name} under wine", "wine",
            [Path.Combine(windowsDotnet, "dotnet.exe"), "test", "Z:" + assembly.Replace('/', '\\')]));
    }
    return steps;
}

List<Step> Gates() =>
[
    .. new[] { "drift", "bindings", "api-coverage", "reconstruction", "out-params" }
        .Select(name => new Step($"kabic check {name}", "dotnet", ["run", "--project", "src/csharp/kabic/Kabic.Cli", "--", "check", name])),
    .. Directory.EnumerateFiles(Path.Combine(rootDir, "scripts"), "check_*.cs").Order()
        .Select(f => new Step(Path.GetFileName(f), "dotnet", ["run", f])),
];

int Run(Step step)
{
    var info = new ProcessStartInfo(step.Command) { WorkingDirectory = rootDir };
    foreach (var a in step.Args) info.ArgumentList.Add(a);
    var lib = Path.Combine(rootDir, "build", "native", "lib");
    var separator = Path.PathSeparator;
    var existing = Environment.GetEnvironmentVariable("LD_LIBRARY_PATH");
    info.Environment["LD_LIBRARY_PATH"] = string.IsNullOrEmpty(existing) ? lib : $"{lib}{separator}{existing}";
    var path = Environment.GetEnvironmentVariable("PATH");
    info.Environment["PATH"] = string.IsNullOrEmpty(path) ? lib : $"{lib}{separator}{path}";
    info.Environment["NUGET_HTTP_CACHE_PATH"] = Path.Combine(rootDir, "build", "nuget", "http-cache");
    var windowsLib = Path.Combine(rootDir, "build", "cross-windows", "lib");
    info.Environment["WINEPATH"] = OperatingSystem.IsWindows() ? windowsLib : "Z:" + windowsLib.Replace('/', '\\');
    using var process = Process.Start(info)!;
    process.WaitForExit();
    return process.ExitCode;
}

record Step(string Name, string Command, string[] Args);
