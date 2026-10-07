#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;

const int Ceiling = 129;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var managedDir = Path.Combine(rootDir, "src", "csharp");

var files = Directory.EnumerateFiles(managedDir, "*.cs", SearchOption.AllDirectories)
    .Select(p => Path.GetRelativePath(rootDir, p).Replace('\\', '/'))
    .Where(p => !Segments(p).Any(s => s is "obj" or "bin" or "Generated" or "generated"))
    .Where(p => !p.EndsWith(".g.cs", StringComparison.Ordinal))
    .Where(p => !p.Contains("/kabic/", StringComparison.Ordinal))
    .OrderBy(p => p, StringComparer.Ordinal)
    .ToList();

var buckets = files.GroupBy(Bucket).OrderByDescending(g => g.Count());
foreach (var b in buckets) Console.WriteLine($"  {b.Count(),4}  {b.Key}");
Console.WriteLine($"  {files.Count,4}  total (ceiling {Ceiling})");

if (files.Count > Ceiling)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine($"{files.Count - Ceiling} hand-written managed file(s) more than the ceiling.");
    Console.Error.WriteLine("Declare the shape in a header and let the backend emit it, or lower");
    Console.Error.WriteLine("nothing and raise nothing -- the ceiling is not a budget to spend.");
    return 1;
}

if (files.Count < Ceiling)
{
    Console.Error.WriteLine();
    Console.Error.WriteLine($"The ceiling is stale: {files.Count} file(s) remain, it says {Ceiling}.");
    Console.Error.WriteLine("Lower it in this script so the progress cannot be given back.");
    return 1;
}

return 0;

static IEnumerable<string> Segments(string path) => path.Split('/');

static string Bucket(string path)
{
    var name = Path.GetFileName(path);
    if (name.EndsWith(".Idiom.cs", StringComparison.Ordinal))
        return "idiom -- a projection the backend does not emit yet";
    if (name == "GlobalUsings.cs")
        return "global usings -- belongs to whatever emits the project";
    if (name.EndsWith("ServiceCollectionExtensions.cs", StringComparison.Ordinal)
        || name.EndsWith("ServiceExtensions.cs", StringComparison.Ordinal))
        return "registration -- derivable from the factory it registers";
    if (name.EndsWith("Module.cs", StringComparison.Ordinal))
        return "module -- a second encarnation of a native module";
    if (path.Contains("/KernelEngine.Cli/", StringComparison.Ordinal))
        return "cli -- project tooling, not a projection";
    if (path.Contains("/KernelEngine.SourceGenerators/", StringComparison.Ordinal))
        return "source generator -- generates, is not generated";
    if (path.Contains(".Abstractions/", StringComparison.Ordinal))
        return "abstraction -- the interface a projection should satisfy";
    return "other -- unclassified, read it and decide";
}
