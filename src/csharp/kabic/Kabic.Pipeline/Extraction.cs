using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;

using Kabic;
using Kabic.Reader;

namespace Kabic.Pipeline;

/// <summary>
/// Extracts the public API of C headers by running zig cc in AST-dump mode.
/// </summary>
public static class Extraction
{
    /// <summary>
    /// The inputs of one extraction: its headers, auxiliary and compose headers, include
    /// directories, zig override and convention.
    /// </summary>
    public sealed record Request(
        IReadOnlyList<string> Headers,
        IReadOnlyList<string> IncludeDirs,
        IReadOnlyList<string> AuxHeaders,
        IReadOnlyList<string> ComposeHeaders,
        string? Zig,
        Convention Convention);

    /// <summary>
    /// Extracts the API of the request and returns it as indented JSON. Throws
    /// <c>InvalidOperationException</c> when zig produces no AST, a header fails to parse, or
    /// the extractor reports errors.
    /// </summary>
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
        var includes = all.Select(h => $"#include \"{h.Replace('\\', '/')}\"").ToList();
        File.WriteAllLines(tuPath, includes);

        JsonObject ast;
        ConstantReader.Typed typed;
        Dictionary<string, string> values = [];
        try
        {
            var written = ConstantReader.Candidates(headerPaths);
            File.WriteAllLines(tuPath, includes.Concat(written.Select(c => ConstantReader.ExpansionProbe(c.Name))));
            var candidates = ConstantReader.Valued(written, Run(zig, tuPath, request.IncludeDirs, ["-E", "-P"]));
            File.WriteAllLines(tuPath, includes.Concat(candidates.Select(c => ConstantReader.TypeProbe(c.Name))));
            ast = JsonNode.Parse(RunAstDump(zig, tuPath, request.IncludeDirs))!.AsObject();
            typed = ConstantReader.ReadTypes(ast, candidates);
            if (typed.Integers.Count > 0)
            {
                File.WriteAllLines(tuPath, includes.Concat(typed.Integers.Select(i => ConstantReader.ValueProbe(i.Name, i.Underlying))));
                values = ConstantReader.ReadValues(JsonNode.Parse(RunAstDump(zig, tuPath, request.IncludeDirs, "-std=c23"))!.AsObject());
            }
        }
        finally
        {
            Directory.Delete(tuDir, recursive: true);
        }

        var sourceBytes = all.Distinct().ToDictionary(Path.GetFullPath, File.ReadAllBytes);
        var (api, errors) = Extractor.Extract(ast, headerPaths.ToHashSet(), sourceBytes, auxPaths.ToHashSet(), composePaths.ToHashSet(), request.Convention.SymbolPrefix);
        errors.AddRange(typed.Errors);
        var byName = typed.Read.ToDictionary(c => c.Name);
        foreach (var i in typed.Integers)
        {
            if (values.TryGetValue(i.Name, out var v)) byName[i.Name] = new ApiConstant(i.Name, i.Spelled, v, null, i.Doc);
            else errors.Add($"{i.Name}: clang folded no value for the macro");
        }
        api.Constants.AddRange(typed.Order.Where(byName.ContainsKey).Select(n => byName[n]));
        if (errors.Count > 0)
            throw new InvalidOperationException(string.Join('\n', errors.Select(e => $"ERROR: {e}")));

        return api.ToJson().ToJsonString(new JsonSerializerOptions { WriteIndented = true });
    }

    /// <summary>
    /// Returns the zig executable: the override when given, else the first zig on the PATH,
    /// else the fallback under the home directory. Throws <c>InvalidOperationException</c> when
    /// none is found.
    /// </summary>
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

    static string RunAstDump(string zig, string tuPath, IReadOnlyList<string> includeDirs, params string[] dialect)
    {
        var stdout = Run(zig, tuPath, includeDirs, [.. dialect, "-Xclang", "-ast-dump=json", "-fsyntax-only", "-fparse-all-comments"]);
        if (stdout.Length < 2 || stdout[0] != '{')
            throw new InvalidOperationException("zig cc produced no AST");
        return stdout;
    }

    static string Run(string zig, string tuPath, IReadOnlyList<string> includeDirs, IReadOnlyList<string> mode)
    {
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(zig) { RedirectStandardOutput = true, RedirectStandardError = true },
        };
        process.StartInfo.Environment["ZIG_LOCAL_CACHE_DIR"] = Path.Combine(Path.GetDirectoryName(tuPath)!, "zig-cache");
        foreach (var a in mode.Prepend("cc").Append(tuPath)) process.StartInfo.ArgumentList.Add(a);
        foreach (var d in includeDirs) { process.StartInfo.ArgumentList.Add("-I"); process.StartInfo.ArgumentList.Add(d); }
        process.Start();
        var stderrTask = process.StandardError.ReadToEndAsync();
        var stdout = process.StandardOutput.ReadToEnd();
        var stderr = stderrTask.Result;
        process.WaitForExit();

        var realErrors = stderr.Split('\n')
            .Where(l => l.Contains("error:") && !l.Contains($"{Path.GetFileName(tuPath)}:1:1: error: FileNotFound"))
            .ToList();
        if (realErrors.Count > 0)
            throw new InvalidOperationException("header failed to parse:\n" + string.Join('\n', realErrors));

        return stdout;
    }
}
