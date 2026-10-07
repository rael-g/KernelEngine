using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Kabic.Frontend;

namespace Kabic.Pipeline;

public static class Extraction
{
    public sealed record Request(
        IReadOnlyList<string> Headers,
        IReadOnlyList<string> IncludeDirs,
        IReadOnlyList<string> AuxHeaders,
        IReadOnlyList<string> ComposeHeaders,
        string? Zig,
        Convention Convention);

    public static string Run(Request request)
    {
        var zig = ResolveZig(request.Zig);
        var headerPaths = request.Headers.Select(Path.GetFullPath).ToList();
        var auxPaths = request.AuxHeaders.Select(Path.GetFullPath).ToList();
        var composePaths = request.ComposeHeaders.Select(Path.GetFullPath).ToList();
        var all = headerPaths.Concat(auxPaths).Concat(composePaths).ToList();

        var tuDir = Path.Combine(Path.GetTempPath(), "kabic_extract_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tuDir);
        var tuPath = Path.Combine(tuDir, "tu.c");
        File.WriteAllLines(tuPath, all.Select(h => $"#include \"{h.Replace('\\', '/')}\""));

        string astJson;
        try
        {
            astJson = RunAstDump(zig, tuPath, request.IncludeDirs);
        }
        finally
        {
            Directory.Delete(tuDir, recursive: true);
        }

        var ast = JsonNode.Parse(astJson)!.AsObject();
        var sourceBytes = all.Distinct().ToDictionary(Path.GetFullPath, File.ReadAllBytes);
        var (api, errors) = Extractor.Extract(ast, Names(headerPaths), sourceBytes, Names(auxPaths), Names(composePaths), request.Convention.SymbolPrefix);
        if (errors.Count > 0)
            throw new InvalidOperationException(string.Join('\n', errors.Select(e => $"ERROR: {e}")));

        return api.ToJson().ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    static HashSet<string> Names(IEnumerable<string> paths) =>
        paths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();

    public static string ResolveZig(string? overridePath)
    {
        if (overridePath is not null) return overridePath;
        var fromPath = FindOnPath("zig");
        if (fromPath is not null) return fromPath;
        var fallback = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "", "zig-x86_64-linux-0.16.0", "zig");
        if (File.Exists(fallback)) return fallback;
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

    static string RunAstDump(string zig, string tuPath, IReadOnlyList<string> includeDirs)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(zig) { RedirectStandardOutput = true, RedirectStandardError = true },
        };
        process.StartInfo.Environment["ZIG_LOCAL_CACHE_DIR"] = Path.Combine(Path.GetDirectoryName(tuPath)!, "zig-cache");
        foreach (var a in new[] { "cc", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-fparse-all-comments", tuPath })
            process.StartInfo.ArgumentList.Add(a);
        foreach (var d in includeDirs) { process.StartInfo.ArgumentList.Add("-I"); process.StartInfo.ArgumentList.Add(d); }
        process.Start();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = stderrTask.Result;
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
}
