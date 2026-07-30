#!/usr/bin/env dotnet run

// KernelEngine Coverage.
//
// Runs the managed (C#) test suite under coverlet, then feeds it through
// ReportGenerator and prints a structured summary.
//
// Usage:
//     dotnet run scripts/coverage.cs            # full pipeline
//     dotnet run scripts/coverage.cs clean      # wipe build/coverage/
//     dotnet run scripts/coverage.cs report     # re-emit summary from cached data
//
// Everything lives under build/coverage/. The script never writes outside it.
//
// C# only. There is no native coverage story: Zig's own compiler has no
// source-coverage instrumentation, and DWARF-based tools (kcov) can't fill
// that gap either — Zig 0.16 emits a line-table extended opcode `libdw`
// (which kcov depends on) doesn't decode, so kcov silently reports 0% for
// any Zig binary regardless of what actually ran. This affects `zig build
// test` targets the same way it affects the two legacy GTest suites
// (tests/c/kernel, tests/integration/cpp) — neither produces real coverage
// data today, so this script no longer tries to build or run them.

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Xml.Linq;

// Report formatting (percentages) must not vary with the host's locale.
CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;

var action = args.Length > 0 ? args[0] : "run";
switch (action)
{
    case "run": Coverage.CmdRun(); break;
    case "clean": Coverage.CmdClean(); break;
    case "report": Coverage.CmdReport(); break;
    default:
        Console.Error.WriteLine($"Unknown action '{action}'. Expected: run, clean, report.");
        return 1;
}
return 0;

static class Coverage
{
    static readonly string BaseDir = Path.GetFullPath(Path.Combine(ScriptPaths.Dir, ".."));
    static readonly string CoverageDir = Path.Combine(BaseDir, "build", "coverage");
    static readonly string ManagedDir = Path.Combine(CoverageDir, "managed");
    static readonly string ReportDir = Path.Combine(CoverageDir, "report");
    static readonly string SummaryTxt = Path.Combine(CoverageDir, "summary.txt");

    const double GapThresholdPct = 30.0;
    const int GapThresholdLines = 50;

    static string Norm(string p) => p.Replace('\\', '/');

    // src/csharp/<project>/... -> <project>
    static string ModuleFor(string path)
    {
        var parts = Norm(path).Split('/');
        return parts.Length >= 3 ? parts[2] : "(unknown)";
    }

    static string Short(string module) => module.Split('/') is { Length: > 0 } parts ? parts[^1] : module;

    // ── Subprocess helper ────────────────────────────────────────────────────

    static int Run(IReadOnlyList<string> cmd, bool check = true, string? cwd = null)
    {
        Console.WriteLine($"  $ {string.Join(' ', cmd)}");
        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(cmd[0]) { WorkingDirectory = cwd ?? "" },
        };
        foreach (var a in cmd.Skip(1)) process.StartInfo.ArgumentList.Add(a);
        process.Start();
        process.WaitForExit();
        if (check && process.ExitCode != 0)
            throw new InvalidOperationException($"Command failed ({process.ExitCode}): {string.Join(' ', cmd)}");
        return process.ExitCode;
    }

    static void Banner(string text)
    {
        Console.WriteLine();
        Console.WriteLine(new string('-', 70));
        Console.WriteLine($"  {text}");
        Console.WriteLine(new string('-', 70));
    }

    // ── Phase 1: managed tests ───────────────────────────────────────────────

    static void RunManagedTests()
    {
        Banner("[1/2] Run managed (C#) tests");
        if (Directory.Exists(ManagedDir)) Directory.Delete(ManagedDir, recursive: true);
        Directory.CreateDirectory(ManagedDir);
        Run([
            "dotnet", "test", Path.Combine(BaseDir, "KernelEngine.slnx"),
            "--collect:XPlat Code Coverage",
            "--results-directory", ManagedDir,
            "--nologo", "-v", "m",
            "--",
            "DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=cobertura",
        ], check: false);
    }

    // ── Phase 2: report ──────────────────────────────────────────────────────

    static void BuildReport()
    {
        Banner("[2/2] Generate report");
        if (Directory.Exists(ReportDir)) Directory.Delete(ReportDir, recursive: true);
        Directory.CreateDirectory(ReportDir);

        var inputs = Directory.Exists(ManagedDir)
            ? Directory.GetFiles(ManagedDir, "*.xml", SearchOption.AllDirectories)
            : [];
        if (inputs.Length == 0)
        {
            Console.WriteLine("  (no coverage data - nothing to report)");
            return;
        }
        Run([
            "reportgenerator",
            "-reports:" + string.Join(';', inputs),
            "-targetdir:" + ReportDir,
            "-reporttypes:Cobertura;Html",
            "-sourcedirs:" + BaseDir,
            "-filefilters:-*Generated*;-*examples*",
            "-classfilters:-*NativeMethods*;-*NativeAnnotation*;-*NativeTypeName*",
        ], check: false);
    }

    // ── Structured summary ───────────────────────────────────────────────────

    class Counts
    {
        public int Covered, Total;
        public double Pct => Total != 0 ? 100.0 * Covered / Total : 0.0;
    }

    static void PrintSummary()
    {
        var cobertura = Path.Combine(ReportDir, "Cobertura.xml");
        if (!File.Exists(cobertura))
        {
            Console.WriteLine("\n  (no Cobertura.xml - run the pipeline first)\n");
            return;
        }

        var root = XDocument.Load(cobertura).Root!;
        var total = new Counts();
        var modules = new Dictionary<string, Counts>();

        var baseUri = Norm(BaseDir).TrimEnd('/') + "/";

        foreach (var clazz in root.Descendants("class"))
        {
            var filePath = Norm(clazz.Attribute("filename")?.Value ?? "");
            if (filePath.StartsWith(baseUri)) filePath = filePath[baseUri.Length..];
            if (!filePath.StartsWith("src/csharp/") || filePath.Contains("/Generated/")) continue;

            var lines = clazz.Descendants("line").ToList();
            if (lines.Count == 0) continue;
            var covered = lines.Count(ln => int.Parse(ln.Attribute("hits")?.Value ?? "0") > 0);
            var lineTotal = lines.Count;

            total.Covered += covered;
            total.Total += lineTotal;
            var module = ModuleFor(filePath);
            if (!modules.TryGetValue(module, out var m)) modules[module] = m = new Counts();
            m.Covered += covered;
            m.Total += lineTotal;
        }

        var outLines = new List<string>();
        void W(string s = "") => outLines.Add(s);

        var now = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        W(new string('=', 70));
        W($"  KernelEngine Coverage (C#) - {now}");
        W(new string('=', 70));
        W();
        W($"  TOTAL                                          {total.Pct,5:F1}%   {total.Covered}/{total.Total}");
        W();
        foreach (var (module, m) in modules.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            W($"    {Short(module),-38} {m.Pct,5:F1}%");
        W();

        var gaps = modules.Where(kv => kv.Value.Total >= GapThresholdLines && kv.Value.Pct < GapThresholdPct)
            .Select(kv => (Module: kv.Key, kv.Value.Pct, kv.Value.Total))
            .OrderBy(g => g.Pct)
            .ToList();
        if (gaps.Count > 0)
        {
            W($"  Critical gaps (< {GapThresholdPct:F0}% AND > {GapThresholdLines} lines):");
            foreach (var (module, p, n) in gaps)
                W($"    - {Short(module),-38} {p,5:F1}%   ({n} lines)");
            W();
        }
        W($"  HTML report: {Path.Combine(ReportDir, "index.html")}");
        W(new string('=', 70));

        var text = string.Join('\n', outLines);
        File.WriteAllText(SummaryTxt, text);
        Console.WriteLine();
        Console.WriteLine(text);
    }

    // ── Subcommands ──────────────────────────────────────────────────────────

    public static void CmdClean()
    {
        if (Directory.Exists(CoverageDir))
        {
            Console.WriteLine($"Removing {CoverageDir}");
            Directory.Delete(CoverageDir, recursive: true);
        }
        else
        {
            Console.WriteLine($"{CoverageDir} does not exist.");
        }
    }

    public static void CmdRun()
    {
        RunManagedTests();
        BuildReport();
        PrintSummary();
    }

    public static void CmdReport() => PrintSummary();
}

static class ScriptPaths
{
    public static string Dir => Impl();
    static string Impl([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
}
