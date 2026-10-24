using System.Text.Json.Nodes;

using Kabic;
using Kabic.Conventions;
using Kabic.Pipeline;
using Kabic.Zig;

namespace Kabic.Cli;

/// <summary>
/// Implements the command that writes one Zig package per contract domain.
/// </summary>
internal static class WriteZigCommand
{
    const string ContractsRoot = "src/c";

    const string PackagesRoot = "src/zig/abi";

    static readonly string[] ExtraIncludes = ["src/zig/common/include"];

    /// <summary>
    /// Writes the package of every domain of the contracts root, under the packages root or the
    /// directory <c>--into</c> names, and returns zero. Returns two when a domain could not be
    /// extracted or laid out.
    /// </summary>
    public static int Run(Options options) => Write(options, options.Into ?? Path.Combine(options.Root, PackagesRoot));

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
            var committed = Path.Combine(options.Root, PackagesRoot);
            var generated = Files(scratch);
            var drift = generated.Union(Files(committed)).Order(StringComparer.Ordinal)
                .Where(rel => !generated.Contains(rel) || !File.Exists(Path.Combine(committed, rel))
                    || !File.ReadAllBytes(Path.Combine(scratch, rel)).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(committed, rel))))
                .ToList();
            foreach (var rel in drift) Console.WriteLine($"[DRIFT] {PackagesRoot}/{rel}");
            if (drift.Count == 0) return 0;
            Console.WriteLine("\n[FAIL] Drift detected! Run 'kabic write zig' and commit the changes.");
            return 1;
        }
        finally
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, recursive: true);
        }
    }

    static HashSet<string> Files(string dir) => Directory.Exists(dir)
        ? Directory.EnumerateFiles(dir, "*", SearchOption.AllDirectories)
            .Select(f => Path.GetRelativePath(dir, f).Replace('\\', '/'))
            .Where(rel => !rel.Split('/').Any(part => part.StartsWith('.'))).ToHashSet()
        : [];

    static int Write(Options options, string into)
    {
        var root = options.Root;
        var convention = ConventionLoader.Load(options.Manifest);
        var contracts = Path.Combine(root, ContractsRoot);
        var domains = Directory.GetDirectories(contracts).Select(Path.GetFileName).OfType<string>()
            .Order(StringComparer.Ordinal).ToList();
        var includeDirs = domains.Select(d => Path.Combine(contracts, d))
            .Concat(ExtraIncludes.Select(d => Path.Combine(root, d))).ToList();

        var models = new System.Collections.Concurrent.ConcurrentDictionary<string, ApiModel>();
        var failures = new System.Collections.Concurrent.ConcurrentDictionary<string, string>();
        Parallel.ForEach(domains, domain =>
        {
            try
            {
                var json = Extraction.Run(new Extraction.Request(HeadersOf(contracts, domain), includeDirs, [], [], options.Zig, convention));
                models[domain] = ApiReader.Read(JsonNode.Parse(json)!.AsObject());
            }
            catch (Exception e) { failures[domain] = e.Message; }
        });
        if (Report(failures)) return 2;

        var owner = new Dictionary<string, string>();
        foreach (var domain in domains)
        {
            var m = models[domain];
            foreach (var name in m.Structs.Select(s => s.Name).Concat(m.Enums.Select(e => e.Name))
                         .Concat(m.TypeAliases.Keys))
                owner.TryAdd(name, domain);
        }
        foreach (var domain in domains)
            foreach (var name in models[domain].Opaques)
                owner.TryAdd(name, domain);

        var texts = new Dictionary<string, string>();
        var imports = new Dictionary<string, List<string>>();
        foreach (var domain in domains)
        {
            var foreign = owner.Where(kv => kv.Value != domain).ToDictionary();
            try { texts[domain] = ZigWriter.Render(models[domain], foreign); }
            catch (NotSupportedException e) { failures[domain] = e.Message; continue; }
            imports[domain] = foreign.Values.Distinct().Where(d => texts[domain].Contains($"@import(\"{d}\")"))
                .Concat(Included(contracts, domain).Where(domains.Contains)).Where(d => d != domain)
                .Distinct().Order(StringComparer.Ordinal).ToList();
        }
        if (Report(failures)) return 2;

        static string Slashed(string path) => path.Replace('\\', '/');
        foreach (var domain in domains)
        {
            var dir = Path.Combine(into, domain);
            var placed = Path.Combine(root, PackagesRoot, domain);
            var reached = Reached(domain, imports);
            var package = new ZigPackage(domain,
                HeadersOf(contracts, domain).Select(h => Slashed(Path.GetRelativePath(Path.Combine(contracts, domain), h))).ToList(),
                imports[domain],
                reached.Select(d => Path.Combine(contracts, d)).Concat(ExtraIncludes.Select(d => Path.Combine(root, d)))
                    .Select(d => Slashed(Path.GetRelativePath(placed, d))).ToList());
            Directory.CreateDirectory(dir);
            File.WriteAllText(Path.Combine(dir, $"{domain}.zig"), texts[domain]);
            File.WriteAllText(Path.Combine(dir, "build.zig"), package.BuildZig());
            File.WriteAllText(Path.Combine(dir, "build.zig.zon"), package.BuildZon());
            File.WriteAllText(Path.Combine(dir, "layout_test.zig"), ZigPackage.LayoutTest(models[domain]));
        }
        File.WriteAllText(Path.Combine(into, "build.zig"), ZigPackage.AllBuildZig(domains));
        File.WriteAllText(Path.Combine(into, "build.zig.zon"), ZigPackage.AllBuildZon(domains));

        Console.WriteLine($"wrote {domains.Count} Zig package(s) under {into}");
        return 0;
    }

    /// <summary>The domain and every domain its imports reach, in name order.</summary>
    static List<string> Reached(string domain, IReadOnlyDictionary<string, List<string>> imports)
    {
        var seen = new SortedSet<string>(StringComparer.Ordinal);
        var pending = new Stack<string>([domain]);
        while (pending.TryPop(out var d))
            if (seen.Add(d)) foreach (var i in imports[d]) pending.Push(i);
        return [.. seen];
    }

    /// <summary>The domains the headers of <paramref name="domain"/> include a header of.</summary>
    static IEnumerable<string> Included(string contracts, string domain) =>
        HeadersOf(contracts, domain).SelectMany(File.ReadLines)
            .Select(l => System.Text.RegularExpressions.Regex.Match(l, @"^\s*#\s*include\s*[<""]kernel_engine/([a-z_]+)/"))
            .Where(m => m.Success).Select(m => m.Groups[1].Value);

    static List<string> HeadersOf(string contracts, string domain) =>
        Directory.GetFiles(Path.Combine(contracts, domain), "*.h", SearchOption.AllDirectories)
            .Order(StringComparer.Ordinal).ToList();

    static bool Report(IReadOnlyDictionary<string, string> failures)
    {
        foreach (var (domain, message) in failures.OrderBy(kv => kv.Key, StringComparer.Ordinal))
            Console.Error.WriteLine($"error: {domain}: {message}");
        return failures.Count > 0;
    }
}
