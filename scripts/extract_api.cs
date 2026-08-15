#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Frontend/Kabic.Frontend.csproj

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using Kabic.Frontend;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? outPath = null;
string? zigOverride = null;
var includeDirs = new List<string>();
var headers = new List<string>();
var auxHeaders = new List<string>();
var composeHeaders = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--out": outPath = args[++i]; break;
        case "--zig": zigOverride = args[++i]; break;
        case "-I": includeDirs.Add(args[++i]); break;
        case "--aux": auxHeaders.Add(args[++i]); break;
        case "--compose": composeHeaders.Add(args[++i]); break;
        default: headers.Add(args[i]); break;
    }
}

if (outPath is null || headers.Count == 0)
{
    Console.Error.WriteLine("usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... "
        + "[--aux <header.h>]... [--compose <header.h>]... <header.h>...");
    return 1;
}

var zig = ResolveZig(zigOverride);
var headerPaths = headers.Select(Path.GetFullPath).ToList();
var auxHeaderPaths = auxHeaders.Select(Path.GetFullPath).ToList();
var composeHeaderPaths = composeHeaders.Select(Path.GetFullPath).ToList();
var headerNames = headerPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();
var auxHeaderNames = auxHeaderPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();
var composeHeaderNames = composeHeaderPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();

var tuDir = Path.Combine(Path.GetTempPath(), "ke_extract_api_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tuDir);
var tuPath = Path.Combine(tuDir, "tu.c");
File.WriteAllLines(tuPath, headerPaths.Concat(auxHeaderPaths).Concat(composeHeaderPaths).Select(h => $"#include \"{h.Replace('\\', '/')}\""));

string astJson;
try
{
    astJson = RunAstDump(zig, tuPath, includeDirs);
}
finally
{
    Directory.Delete(tuDir, recursive: true);
}

var ast = JsonNode.Parse(astJson)!.AsObject();

var sourceBytes = headerPaths.Concat(auxHeaderPaths).Concat(composeHeaderPaths).Distinct().ToDictionary(Path.GetFullPath, File.ReadAllBytes);

var (api, errors) = Extractor.Extract(ast, headerNames, sourceBytes, auxHeaderNames, composeHeaderNames);

if (errors.Count > 0)
{
    foreach (var e in errors) Console.Error.WriteLine($"ERROR: {e}");
    return 1;
}

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
File.WriteAllText(outPath, api.ToJson().ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

var vtableCount = api.Structs.Count(s => s.IsVtable);
Console.WriteLine($"wrote {outPath}: enums={api.Enums.Count} structs={api.Structs.Count - vtableCount} "
    + $"vtables={vtableCount} functions={api.Functions.Count}");
return 0;

static string ResolveZig(string? overridePath)
{
    if (overridePath is not null) return overridePath;
    var fromPath = FindOnPath("zig");
    if (fromPath is not null) return fromPath;
    var distrobox = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "",
        "zig-x86_64-linux-0.16.0", "zig");
    if (File.Exists(distrobox)) return distrobox;
    throw new InvalidOperationException("zig not found on PATH; pass --zig <path>");
}

static string? FindOnPath(string exe)
{
    var path = Environment.GetEnvironmentVariable("PATH") ?? "";
    foreach (var dir in path.Split(Path.PathSeparator))
    {
        var candidate = Path.Combine(dir, exe);
        if (File.Exists(candidate)) return candidate;
    }
    return null;
}

static string RunAstDump(string zig, string tuPath, List<string> includeDirs)
{
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo(zig)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        },
    };
    foreach (var a in new[] { "cc", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-fparse-all-comments", tuPath })
        process.StartInfo.ArgumentList.Add(a);
    foreach (var d in includeDirs) { process.StartInfo.ArgumentList.Add("-I"); process.StartInfo.ArgumentList.Add(d); }
    process.Start();
    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();

    if (stdout.Length < 2 || stdout[0] != '{')
        throw new InvalidOperationException($"zig cc produced no AST:\n{stderr}");

    var realErrors = stderr.Split('\n')
        .Where(l => l.Contains("error:") && !l.Contains($"{Path.GetFileName(tuPath)}:1:1: error: FileNotFound"))
        .ToList();
    if (realErrors.Count > 0)
        throw new InvalidOperationException("header failed to parse:\n" + string.Join('\n', realErrors));

    return stdout;
}
