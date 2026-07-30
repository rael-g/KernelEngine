#!/usr/bin/env dotnet run

// KernelEngine Coverage.
//
// Builds + runs the test suite under Clang source-based coverage instrumentation
// (native: -fprofile-instr-generate / .profraw / llvm-profdata / llvm-cov;
// managed: dotnet test + coverlet), then merges both worlds into a single
// ReportGenerator output and prints a structured summary.
//
// Usage:
//     dotnet run scripts/coverage.cs            # full pipeline
//     dotnet run scripts/coverage.cs clean      # wipe build/coverage/
//     dotnet run scripts/coverage.cs report     # re-emit summary from cached data
//
// Everything lives under build/coverage/. The script never writes outside it.
//
// Native coverage scope: almost all engine logic is Zig source, which Zig's own
// linker compiles/links directly — it does not go through Clang, so instrumenting
// every C/C++ translation unit under src/ does not apply. The two GTest suites are
// the one exception — their build.zig shells out to the SYSTEM clang++ directly
// for both compile and link (an ABI workaround already in place, see
// tests/c/kernel/build.zig), so -Dcoverage=true there produces real, valid
// instrumented binaries. That still surfaces meaningful native signal beyond just
// the test files themselves: contract headers with inline definitions get
// instrumented too, since they're #include'd straight into the test translation
// units.

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
    static readonly string ZigOutDir = Path.Combine(CoverageDir, "zig-out");
    static readonly string ProfrawsDir = Path.Combine(CoverageDir, "profraws");
    static readonly string ManagedDir = Path.Combine(CoverageDir, "managed");
    static readonly string ReportDir = Path.Combine(CoverageDir, "report");
    static readonly string MergedProfdata = Path.Combine(CoverageDir, "merged.profdata");
    static readonly string NativeLcov = Path.Combine(CoverageDir, "native.lcov");
    static readonly string SummaryTxt = Path.Combine(CoverageDir, "summary.txt");

    static readonly string[] NativeTestBinaries = ["test_ke_kernel", "test_integration_cpp"];

    // L3 (auto-generated C# bindings under */Native/Generated/) is excluded from
    // analysis up front. "Native" is no longer split into kernel/plugin layers:
    // see the file header for why only the GTest suites' own translation units
    // (plus any contract headers they #include) are instrumented today.
    static readonly (string Id, string Name, Func<string, bool> Predicate)[] Layers =
    [
        ("L2", "Native (GTest suites + included headers)",
            p => Norm(p).StartsWith("tests/") || Norm(p).StartsWith("src/c/")),
        ("L4", "C# framework",
            p => Norm(p).StartsWith("src/csharp/") && !Norm(p).Contains("/Generated/")),
    ];

    const double GapThresholdPct = 30.0;
    const int GapThresholdLines = 50;

    static string Norm(string p) => p.Replace('\\', '/');

    // ── Subprocess helpers ───────────────────────────────────────────────────

    static int Run(IReadOnlyList<string> cmd, IReadOnlyDictionary<string, string>? env = null,
        bool check = true, string? cwd = null, string? stdoutFile = null)
    {
        // Long argv (e.g. thousands of profraw paths) is uninteresting noise.
        // Show only the program name and a count of the rest.
        Console.WriteLine(cmd.Count > 6
            ? $"  $ {cmd[0]} ... ({cmd.Count - 1} args)"
            : $"  $ {string.Join(' ', cmd)}");

        using var process = new Process
        {
            StartInfo = new ProcessStartInfo(cmd[0])
            {
                WorkingDirectory = cwd ?? "",
                RedirectStandardOutput = stdoutFile is not null,
            },
        };
        foreach (var a in cmd.Skip(1)) process.StartInfo.ArgumentList.Add(a);
        if (env is not null)
            foreach (var (k, v) in env) process.StartInfo.Environment[k] = v;

        process.Start();
        if (stdoutFile is not null)
        {
            using var writer = new StreamWriter(stdoutFile);
            writer.Write(process.StandardOutput.ReadToEnd());
        }
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

    // ── Phase 1: build ───────────────────────────────────────────────────────

    static void ConfigureAndBuild()
    {
        Banner("[1/4] Build (root build.zig, -Dcoverage=true for the GTest suites)");
        var vcpkgRoot = Environment.GetEnvironmentVariable("VCPKG_ROOT");
        List<string> cmdArgs = ["zig", "build", "--prefix", ZigOutDir, "-Dcoverage=true"];
        if (vcpkgRoot is not null) cmdArgs.Add($"-Dvcpkg-root={vcpkgRoot}");
        Run(cmdArgs, cwd: BaseDir);
    }

    // ── Phase 2: native tests + profile merge ───────────────────────────────

    static List<string> RunNativeTests()
    {
        Banner("[2/4] Run native tests (instrumented GTest suites)");
        if (Directory.Exists(ProfrawsDir)) Directory.Delete(ProfrawsDir, recursive: true);
        Directory.CreateDirectory(ProfrawsDir);
        var binDir = Path.Combine(ZigOutDir, "bin");
        var binaries = new List<string>();
        foreach (var name in NativeTestBinaries)
        {
            var exe = Path.Combine(binDir, OperatingSystem.IsWindows() ? $"{name}.exe" : name);
            if (!File.Exists(exe))
            {
                Console.WriteLine($"  (missing {exe} - skipping)");
                continue;
            }
            binaries.Add(exe);
            // %p (PID) + %m (per-binary id) keeps every run's profraw unique.
            var env = new Dictionary<string, string>
            {
                ["LLVM_PROFILE_FILE"] = Path.Combine(ProfrawsDir, $"{name}-%p-%m.profraw"),
            };
            Run([exe], env: env, check: false);
        }
        return binaries;
    }

    static bool MergeNativeProfile(List<string> binaries)
    {
        var profraws = Directory.Exists(ProfrawsDir)
            ? Directory.GetFiles(ProfrawsDir, "*.profraw")
            : [];
        if (profraws.Length == 0)
        {
            Console.WriteLine("  (no .profraw produced - skipping native LCOV export)");
            return false;
        }
        Console.WriteLine($"  Merging {profraws.Length} profraw files -> {Path.GetFileName(MergedProfdata)}");
        var profrawList = Path.Combine(CoverageDir, "profraws.list");
        File.WriteAllText(profrawList, string.Join('\n', profraws));
        Run(["llvm-profdata", "merge", "-sparse", $"-o={MergedProfdata}", "-f", profrawList]);

        if (binaries.Count == 0)
        {
            Console.WriteLine("  (no instrumented binaries ran - skipping native LCOV export)");
            return false;
        }
        Console.WriteLine($"  Exporting LCOV across {binaries.Count} binaries -> {Path.GetFileName(NativeLcov)}");
        var first = binaries[0];
        var rest = binaries.Skip(1);
        List<string> cmd = ["llvm-cov", "export", "-format=lcov", $"-instr-profile={MergedProfdata}", first];
        cmd.AddRange(rest.Select(p => $"-object={p}"));
        Run(cmd, cwd: BaseDir, stdoutFile: NativeLcov);
        return true;
    }

    // ── Phase 3: managed tests ───────────────────────────────────────────────

    static void RunManagedTests()
    {
        Banner("[3/4] Run managed (C#) tests");
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

    // ── Phase 4: unified report ──────────────────────────────────────────────

    static void BuildReport()
    {
        Banner("[4/4] Generate unified report");
        if (Directory.Exists(ReportDir)) Directory.Delete(ReportDir, recursive: true);
        Directory.CreateDirectory(ReportDir);

        var inputs = new List<string>();
        if (File.Exists(NativeLcov) && new FileInfo(NativeLcov).Length > 0)
            inputs.Add(NativeLcov);
        if (Directory.Exists(ManagedDir))
            inputs.AddRange(Directory.GetFiles(ManagedDir, "*.xml", SearchOption.AllDirectories));

        if (inputs.Count == 0)
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
            // *tests* is no longer excluded: the GTest suites' own .cpp files are
            // now the primary native coverage signal (see file header).
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

    static string ModuleFor(string layer, string path)
    {
        var parts = Norm(path).Split('/');
        return layer switch
        {
            // tests/c/kernel/... -> tests/c/kernel ; src/c/<domain>/... -> src/c/<domain>
            "L2" => parts.Length >= 3 ? string.Join('/', parts[..3]) : string.Join('/', parts),
            // src/csharp/<project>/... -> <project>
            "L4" => parts.Length >= 3 ? parts[2] : "(unknown)",
            _ => "(unknown)",
        };
    }

    static string Short(string module) => module.Split('/') is { Length: > 0 } parts ? parts[^1] : module;

    static void PrintSummary()
    {
        var cobertura = Path.Combine(ReportDir, "Cobertura.xml");
        if (!File.Exists(cobertura))
        {
            Console.WriteLine("\n  (no Cobertura.xml - run the pipeline first)\n");
            return;
        }

        var root = XDocument.Load(cobertura).Root!;

        var perLayer = Layers.ToDictionary(l => l.Id, _ => new
        {
            Totals = new Counts(),
            Modules = new Dictionary<string, Counts>(),
        });
        var native = new Counts();
        var managed = new Counts();

        var baseUri = Norm(BaseDir).TrimEnd('/') + "/";

        foreach (var clazz in root.Descendants("class"))
        {
            var filePath = Norm(clazz.Attribute("filename")?.Value ?? "");
            if (filePath.StartsWith(baseUri)) filePath = filePath[baseUri.Length..];

            var lines = clazz.Descendants("line").ToList();
            if (lines.Count == 0) continue;
            var covered = lines.Count(ln => int.Parse(ln.Attribute("hits")?.Value ?? "0") > 0);
            var lineTotal = lines.Count;

            foreach (var (id, _, predicate) in Layers)
            {
                if (!predicate(filePath)) continue;
                var l = perLayer[id];
                l.Totals.Covered += covered;
                l.Totals.Total += lineTotal;
                var module = ModuleFor(id, filePath);
                if (!l.Modules.TryGetValue(module, out var m)) l.Modules[module] = m = new Counts();
                m.Covered += covered;
                m.Total += lineTotal;
                var bucket = id == "L2" ? native : managed;
                bucket.Covered += covered;
                bucket.Total += lineTotal;
                break;
            }
        }

        var total = new Counts { Covered = native.Covered + managed.Covered, Total = native.Total + managed.Total };

        var outLines = new List<string>();
        void W(string s = "") => outLines.Add(s);

        var now = DateTime.Now.ToString("yyyy-MM-dd HH:mm");
        W(new string('=', 70));
        W($"  KernelEngine Coverage - {now}");
        W(new string('=', 70));
        W();
        W($"  TOTAL                                          {total.Pct,5:F1}%   {total.Covered}/{total.Total}");
        W();
        W($"  Native  (C/C++)                                {native.Pct,5:F1}%   {native.Covered}/{native.Total}");
        W($"  Managed (C#)                                   {managed.Pct,5:F1}%   {managed.Covered}/{managed.Total}");
        W();
        W("  Per layer:");
        foreach (var (id, name, _) in Layers)
        {
            var l = perLayer[id];
            W($"    {id} - {name,-22} {l.Totals.Pct,5:F1}%   {l.Totals.Covered}/{l.Totals.Total}");
            foreach (var (module, m) in l.Modules.OrderBy(kv => kv.Key, StringComparer.Ordinal))
                W($"        {Short(module),-38} {m.Pct,5:F1}%");
        }
        W();

        var gaps = new List<(string Module, double Pct, int Total)>();
        foreach (var (id, _, _) in Layers)
            foreach (var (module, m) in perLayer[id].Modules)
                if (m.Total >= GapThresholdLines && m.Pct < GapThresholdPct)
                    gaps.Add((module, m.Pct, m.Total));

        if (gaps.Count > 0)
        {
            W($"  Critical gaps (< {GapThresholdPct:F0}% AND > {GapThresholdLines} lines):");
            foreach (var (module, p, n) in gaps.OrderBy(g => g.Pct))
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
        ConfigureAndBuild();
        var binaries = RunNativeTests();
        MergeNativeProfile(binaries);
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
