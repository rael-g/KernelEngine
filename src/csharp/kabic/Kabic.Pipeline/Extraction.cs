using System.Diagnostics;
using System.Text.Json;
using System.Text.Json.Nodes;
using Kabic.Frontend;

namespace Kabic.Pipeline;

/// <summary>
/// Extracts the public API of C headers by running zig cc in AST-dump mode.
/// </summary>
/// <remarks>
/// Run resolves the zig executable and writes one translation unit that includes the headers,
/// then the auxiliary headers, then the compose headers, into a scratch directory.
/// <c>RunAstDump</c> parses that unit, and the scratch directory is deleted in a finally block.
/// The bytes of every header are read, and the AST is given to <c>Extractor.Extract</c> with
/// the file names of each header group and the symbol prefix of the convention. Extractor
/// errors are raised as one <c>InvalidOperationException</c>; otherwise the API is written as
/// indented JSON. <c>RunAstDump</c> points the zig cache into the scratch directory. It fails
/// when stdout does not start with a JSON object, or when stderr holds an error line other than
/// the file-not-found error of the unit itself.
/// </remarks>
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
