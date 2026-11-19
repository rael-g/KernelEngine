#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Xml.Linq;

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
    static readonly string NativePrefix = Path.Combine(BaseDir, "build", "native");
    static readonly string ZigCobertura = Path.Combine(NativePrefix, "coverage", "kcov-merged", "cobertura.xml");

    const double GapThresholdPct = 30.0;
    const int GapThresholdLines = 50;

    static string Norm(string p) => p.Replace('\\', '/');

    static string ModuleFor(string path)
    {
        var parts = Norm(path).Split('/');
        return parts.Length >= 3 ? parts[2] : "(unknown)";
    }

    static string Short(string module) => module.Split('/') is { Length: > 0 } parts ? parts[^1] : module;

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

    static void RunManagedTests()
    {
        Banner("[1/3] Run managed (C#) tests");
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

    static void BuildReport()
    {
        Banner("[2/3] Generate report");
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
        Run(["dotnet", "tool", "restore"], cwd: BaseDir);
        Run([
            "dotnet", "tool", "run", "reportgenerator", "--",
            "-reports:" + string.Join(';', inputs),
            "-targetdir:" + ReportDir,
            "-reporttypes:Cobertura;Html",
            "-sourcedirs:" + BaseDir,
            "-filefilters:-*Generated*;-*.g.cs;-*examples*",
            "-classfilters:-*NativeMethods*;-*NativeAnnotation*;-*NativeTypeName*",
        ], check: false, cwd: BaseDir);
    }

    static void RunZigTests()
    {
        Banner("[3/3] Run the Zig tests under kcov");
        Run([
            "zig", "build", "coverage", "-Dcoverage",
            "--prefix", NativePrefix,
            "--global-cache-dir", Path.Combine(BaseDir, "build", "zig-global"),
        ], check: false, cwd: BaseDir);
    }

    class Counts
    {
        public int Covered, Total;
        public double Pct => Total != 0 ? 100.0 * Covered / Total : 0.0;
    }

    static Dictionary<string, Counts>? Read(string cobertura, Func<string, string?> moduleOf, Counts total)
    {
        if (!File.Exists(cobertura)) return null;
        var modules = new Dictionary<string, Counts>();
        foreach (var clazz in XDocument.Load(cobertura).Root!.Descendants("class"))
        {
            var module = moduleOf(Norm(clazz.Attribute("filename")?.Value ?? ""));
            if (module is null) continue;
            var lines = clazz.Descendants("line").ToList();
            if (lines.Count == 0) continue;
            var covered = lines.Count(ln => int.Parse(ln.Attribute("hits")?.Value ?? "0") > 0);
            total.Covered += covered;
            total.Total += lines.Count;
            if (!modules.TryGetValue(module, out var m)) modules[module] = m = new Counts();
            m.Covered += covered;
            m.Total += lines.Count;
        }
        return modules;
    }

    static string? ManagedModule(string filePath)
    {
        var baseUri = Norm(BaseDir).TrimEnd('/') + "/";
        if (filePath.StartsWith(baseUri)) filePath = filePath[baseUri.Length..];
        if (!filePath.StartsWith("src/csharp/") || filePath.Contains("/Generated/") || filePath.EndsWith(".g.cs")) return null;
        return Short(ModuleFor(filePath));
    }

    static string? ZigModule(string filePath)
    {
        var at = filePath.IndexOf("/src/", StringComparison.Ordinal);
        return at > 0 ? filePath[..at] : Path.GetDirectoryName(filePath)?.Replace('\\', '/');
    }

    static void Section(List<string> outLines, string title, string cobertura, Func<string, string?> moduleOf, string missing)
    {
        void W(string s = "") => outLines.Add(s);
        var total = new Counts();
        var modules = Read(cobertura, moduleOf, total);
        W($"  {title}");
        if (modules is null)
        {
            W($"    ({missing})");
            W();
            return;
        }
        W($"    {"TOTAL",-38} {total.Pct,5:F1}%   {total.Covered,6}/{total.Total}");
        W();
        foreach (var (module, m) in modules.OrderBy(kv => kv.Value.Pct).ThenBy(kv => kv.Key, StringComparer.Ordinal))
            W($"    {module,-38} {m.Pct,5:F1}%   {m.Covered,6}/{m.Total}");
        W();
        var gaps = modules.Where(kv => kv.Value.Total >= GapThresholdLines && kv.Value.Pct < GapThresholdPct).ToList();
        if (gaps.Count > 0)
        {
            W($"    Critical gaps (< {GapThresholdPct:F0}% AND > {GapThresholdLines} lines): {string.Join(", ", gaps.Select(g => g.Key))}");
            W();
        }
        W($"    HTML report: {Path.Combine(Path.GetDirectoryName(cobertura)!, "index.html")}");
        W();
    }

    static void PrintSummary()
    {
        var outLines = new List<string>();
        var now = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        outLines.Add(new string('=', 70));
        outLines.Add($"  KernelEngine Coverage - {now}");
        outLines.Add(new string('=', 70));
        outLines.Add("");
        Section(outLines, "C#", Path.Combine(ReportDir, "Cobertura.xml"), ManagedModule, "no Cobertura.xml - run the pipeline first");
        Section(outLines, "Zig", ZigCobertura, ZigModule, "no kcov report - run zig build coverage -Dcoverage");
        outLines.Add(new string('=', 70));

        var text = string.Join('\n', outLines);
        Directory.CreateDirectory(CoverageDir);
        File.WriteAllText(SummaryTxt, text);
        Console.WriteLine();
        Console.WriteLine(text);
    }

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
        RunZigTests();
        PrintSummary();
    }

    public static void CmdReport() => PrintSummary();
}

static class ScriptPaths
{
    public static string Dir => Impl();
    static string Impl([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
}
