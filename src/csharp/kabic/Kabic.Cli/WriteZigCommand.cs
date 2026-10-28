using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

using Kabic;
using Kabic.Conventions;
using Kabic.Pipeline;
using Kabic.Zig;

namespace Kabic.Cli;

/// <summary>
/// Implements the command that writes one Zig package per contract domain and one per plugin's
/// factory headers.
/// </summary>
internal static class WriteZigCommand
{
    const string ContractsRoot = "src/c";

    const string PluginsRoot = "src/zig";

    const string PackagesRoot = "src/zig/abi";

    const string FactoryPackageDir = "abi";

    const string FactorySuffix = "_factory";

    const string FactoryPackagePrefix = "abi_";

    const string PluginPrefix = "ke_";

    static readonly string[] SharedIncludes = ["src/zig/common/include"];

    /// <summary>
    /// The headers under one include root and where their package is written. A domain's root is
    /// its contract directory; a plugin's is its <c>include</c> directory.
    /// </summary>
    sealed record Unit(string Key, string Package, string IncludeRoot, string PackageDir, bool Factory)
    {
        public List<string> Headers { get; } = Directory.GetFiles(IncludeRoot, "*.h", SearchOption.AllDirectories)
            .Order(StringComparer.Ordinal).ToList();
    }

    /// <summary>
    /// Writes every package in place, or under the directory <c>--into</c> names as if it were
    /// the repository root, and returns zero. Returns two when headers could not be extracted
    /// or laid out.
    /// </summary>
    public static int Run(Options options) => Write(options, options.Into ?? options.Root);

    /// <summary>
    /// Writes the packages into a scratch directory and compares them with the committed ones.
    /// Returns zero when they are the same, one when they differ, and two when they could not
    /// be written.
    /// </summary>
    public static int CheckDrift(Options options)
    {
        var scratch = Path.Combine(Path.GetTempPath(), "kabic_zig_check_" + Guid.NewGuid().ToString("N")[..8]);
        try
        {
            if (Write(options, scratch) is var code and not 0) return code;
            var generated = Files(scratch, [""]);
            var committed = Files(options.Root, [PackagesRoot, .. Units(options.Root).Where(u => u.Factory)
                .Select(u => Slashed(Path.GetRelativePath(options.Root, u.PackageDir)))]);
            var drift = generated.Union(committed).Order(StringComparer.Ordinal)
                .Where(rel => !generated.Contains(rel) || !committed.Contains(rel)
                    || !File.ReadAllBytes(Path.Combine(scratch, rel)).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(options.Root, rel))))
                .ToList();
            foreach (var rel in drift) Console.WriteLine($"[DRIFT] {rel}");
            if (drift.Count == 0) return 0;
            Console.WriteLine("\n[FAIL] Drift detected! Run 'kabic write zig' and commit the changes.");
            return 1;
        }
        finally
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, recursive: true);
        }
    }

    static HashSet<string> Files(string root, IEnumerable<string> dirs) =>
        dirs.Select(d => Path.Combine(root, d)).Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(d, "*", SearchOption.AllDirectories))
            .Select(f => Slashed(Path.GetRelativePath(root, f)))
            .Where(rel => !rel.Split('/').Any(part => part.StartsWith('.'))).ToHashSet();

    static string Slashed(string path) => path.Replace('\\', '/');

    static List<Unit> Units(string root)
    {
        var contracts = Path.Combine(root, ContractsRoot);
        var domains = Directory.GetDirectories(contracts).Order(StringComparer.Ordinal)
            .Select(d => new Unit(Path.GetFileName(d), ZigPackage.DomainPackage(Path.GetFileName(d)), d, Path.Combine(root, PackagesRoot, Path.GetFileName(d)), false));
        var shared = SharedIncludes.Select(s => Path.GetFullPath(Path.Combine(root, s))).ToHashSet();
        var plugins = Directory.GetDirectories(Path.Combine(root, PluginsRoot), "include", SearchOption.AllDirectories)
            .Where(d => Directory.Exists(Path.Combine(d, "kernel_engine")) && !shared.Contains(Path.GetFullPath(d)))
            .Where(d => !Slashed(Path.GetRelativePath(root, d)).Split('/').Any(part => part.StartsWith('.')))
            .Select(d => Path.GetDirectoryName(d)!)
            .Order(StringComparer.Ordinal)
            .Select(p => (Dir: p, Name: PluginName(p)))
            .Select(p => new Unit(p.Name + FactorySuffix, FactoryPackagePrefix + p.Name, Path.Combine(p.Dir, "include"),
                Path.Combine(p.Dir, FactoryPackageDir), true));
        return [.. domains, .. plugins];
    }

    /// <summary>The package name the plugin at <paramref name="dir"/> declares, without its prefix.</summary>
    static string PluginName(string dir)
    {
        var zon = Path.Combine(dir, "build.zig.zon");
        var name = File.Exists(zon) ? Regex.Match(File.ReadAllText(zon), @"\.name\s*=\s*\.(\w+)").Groups[1].Value : "";
        if (name.Length == 0) throw new InvalidOperationException($"{zon} names no package");
        return name.StartsWith(PluginPrefix, StringComparison.Ordinal) ? name[PluginPrefix.Length..] : name;
    }

    static int Write(Options options, string into)
    {
        var root = options.Root;
        var convention = ConventionLoader.Load(options.Manifest);
        var units = Units(root);
        var includeDirs = units.Select(u => u.IncludeRoot).Concat(SharedIncludes.Select(d => Path.Combine(root, d))).ToList();

        var models = new System.Collections.Concurrent.ConcurrentDictionary<string, ApiModel>();
        var failures = new System.Collections.Concurrent.ConcurrentDictionary<string, string>();
        Parallel.ForEach(units, unit =>
        {
            try
            {
                var json = Extraction.Run(new Extraction.Request(unit.Headers, includeDirs, [], [], options.Zig, convention));
                models[unit.Key] = ApiReader.Read(JsonNode.Parse(json)!.AsObject());
            }
            catch (Exception e) { failures[unit.Key] = e.Message; }
        });
        if (Report(failures)) return 2;

        var owner = new Dictionary<string, string>();
        foreach (var unit in units)
        {
            var m = models[unit.Key];
            foreach (var name in m.Structs.Select(s => s.Name).Concat(m.Enums.Select(e => e.Name))
                         .Concat(m.TypeAliases.Keys))
                owner.TryAdd(name, unit.Key);
        }
        foreach (var unit in units)
            foreach (var name in models[unit.Key].Opaques)
                owner.TryAdd(name, unit.Key);
        foreach (var unit in units)
            foreach (var name in models[unit.Key].Enums.Where(e => !e.External).SelectMany(e => e.Values).Select(v => v.Name)
                         .Concat(models[unit.Key].Constants.Select(c => c.Name)))
                owner.TryAdd(name, unit.Key);
        var records = new Dictionary<string, ApiStruct>();
        foreach (var s in units.SelectMany(u => models[u.Key].Structs).Where(s => !s.External)) records.TryAdd(s.Name, s);
        ApiModel Composed(string key)
        {
            var composed = new ApiModel();
            foreach (var u in units)
            {
                var m = models[u.Key];
                var own = u.Key == key;
                composed.Structs.AddRange(m.Structs.Where(s => !s.External).Select(s => own ? s : s with { External = true }));
                composed.Enums.AddRange(m.Enums.Where(e => !e.External).Select(e => own ? e : e with { External = true }));
                foreach (var (alias, target) in m.TypeAliases) composed.TypeAliases.TryAdd(alias, target);
                if (own) composed.Statics.AddRange(m.Statics);
            }
            return composed;
        }

        var texts = new Dictionary<string, string>();
        var imports = new Dictionary<string, List<string>>();
        foreach (var unit in units)
        {
            var foreign = owner.Where(kv => kv.Value != unit.Key).ToDictionary();
            try { texts[unit.Key] = ZigWriter.Render(models[unit.Key], foreign, unit.Factory, new ZigWriter.FieldTableContext(convention, records, Composed(unit.Key))); }
            catch (NotSupportedException e) { failures[unit.Key] = e.Message; continue; }
            imports[unit.Key] = foreign.Values.Distinct().Where(k => texts[unit.Key].Contains($"@import(\"{k}\")"))
                .Concat(Included(unit, units)).Where(k => k != unit.Key)
                .Distinct().Order(StringComparer.Ordinal).ToList();
        }
        if (Report(failures)) return 2;

        var byKey = units.ToDictionary(u => u.Key);
        foreach (var unit in units)
        {
            var dir = Path.Combine(into, Path.GetRelativePath(root, unit.PackageDir));
            var package = new ZigPackage(unit.Key, unit.Package,
                unit.Headers.Select(h => Slashed(Path.GetRelativePath(unit.IncludeRoot, h))).ToList(),
                imports[unit.Key].Select(k => new ZigImport(k, byKey[k].Package, Slashed(Path.GetRelativePath(unit.PackageDir, byKey[k].PackageDir)))).ToList(),
                Reached(unit.Key, imports).Select(k => byKey[k].IncludeRoot).Concat(SharedIncludes.Select(d => Path.Combine(root, d)))
                    .Select(d => Slashed(Path.GetRelativePath(unit.PackageDir, d))).ToList());
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, $"{unit.Key}.zig"), texts[unit.Key]);
            File.WriteAllText(Path.Combine(dir, "build.zig"), package.BuildZig());
            File.WriteAllText(Path.Combine(dir, "build.zig.zon"), package.BuildZon());
            File.WriteAllText(Path.Combine(dir, "layout_test.zig"), ZigPackage.LayoutTest(models[unit.Key], ZigWriter.TablesOf(Composed(unit.Key), convention).Select(t => t.Table).ToList()));
        }
        var all = Path.Combine(root, PackagesRoot);
        var gathered = units.Select(u => new ZigImport(u.Key, u.Package, Slashed(Path.GetRelativePath(all, u.PackageDir)))).ToList();
        Directory.CreateDirectory(Path.Combine(into, PackagesRoot));
        File.WriteAllText(Path.Combine(into, PackagesRoot, "build.zig"), ZigPackage.AllBuildZig(gathered));
        File.WriteAllText(Path.Combine(into, PackagesRoot, "build.zig.zon"), ZigPackage.AllBuildZon(gathered));

        Console.WriteLine($"wrote {units.Count} Zig package(s) under {into}");
        return 0;
    }

    /// <summary>The unit and every unit its imports reach, in key order.</summary>
    static List<string> Reached(string key, IReadOnlyDictionary<string, List<string>> imports)
    {
        var seen = new SortedSet<string>(StringComparer.Ordinal);
        var pending = new Stack<string>([key]);
        while (pending.TryPop(out var k))
            if (seen.Add(k)) foreach (var i in imports[k]) pending.Push(i);
        return [.. seen];
    }

    /// <summary>The units whose include root holds a header the headers of <paramref name="unit"/> include.</summary>
    static IEnumerable<string> Included(Unit unit, IReadOnlyList<Unit> units) =>
        unit.Headers.SelectMany(File.ReadLines)
            .Select(l => Regex.Match(l, @"^\s*#\s*include\s*[<""](kernel_engine/[^>""]+)[>""]"))
            .Where(m => m.Success)
            .SelectMany(m => units.Where(u => File.Exists(Path.Combine(u.IncludeRoot, m.Groups[1].Value))).Select(u => u.Key).Take(1));

    static bool Report(IReadOnlyDictionary<string, string> failures)
    {
        foreach (var (key, message) in failures.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            Console.Error.WriteLine($"error: {key}: {message}");
        return failures.Count > 0;
    }
}
