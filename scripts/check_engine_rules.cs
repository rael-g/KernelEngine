#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

var tracked = Tracked(rootDir)
    .Where(p => !Segments(p).Any(s => s is "third_party" or "Generated" or "generated"))
    .Where(p => !p.EndsWith(".g.cs", StringComparison.Ordinal))
    .OrderBy(p => p, StringComparer.Ordinal)
    .ToList();

if (tracked.Count == 0)
{
    Console.Error.WriteLine("no source file was found; no rule can be checked");
    return 1;
}

var sources = tracked.ToDictionary(p => p, p => File.ReadAllLines(Path.Combine(rootDir, p)));

var cppFixture = "src/zig/common/test/cpp_static_init_probe.cpp";
var abort = new Regex(@"std\.debug\.assert|\bassert\(|@panic\(|process\.abort|std\.debug\.panic|\babort\(");
var crashOnFailure = new Regex(@"\b(catch|orelse) unreachable\b");
var threading = new Regex(@"std\.Thread\.(Mutex|Condition|RwLock|Semaphore|ResetEvent|spawn)|pthread_");
var pinning = new Regex(@"pinnedThread:|\.DispatchPinned\(|dispatch_pinned\.\?\(|\.pinned_thread = [1-9]");
var exportMacro = new Regex(@"\bKE_[A-Z_]*API\b");
var plainFunction = new Regex(@"^(?!typedef)[A-Za-z_][A-Za-z0-9_ \*]*\bke_[a-z0-9_]+\s*\(.*\)\s*;");
var bagName = new Regex(@"\bke_[a-z0-9_]*_(desc|descriptor|info|config)\b");
var implName = new Regex(@"(?<![A-Za-z0-9])impl_[a-z]|[a-z0-9]Impl\b|[a-z0-9]_impl\b");
var slashComment = new Regex(@"^\s*//(?![/!])");
var hashComment = new Regex(@"^\s*#(?!!)");
var shaderBindingNumber = new Regex(@"vk::binding\s*\(|:\s*register\s*\(");
var bindingNumber = new Regex(@"\.binding\s*=\s*[0-9]");
var blockComment = new Regex(@"/\*(?![*!])");
var exportFn = new Regex(@"^\s*(?:pub )?export fn (\w+)");
var declared = new Regex(@"^\s*KE_\w*API\s[^;{#]*?\b(\w+)\s*\(", RegexOptions.Multiline);

var plugins = sources.Where(s => s.Key.StartsWith("src/zig/", StringComparison.Ordinal)).ToList();
var zig = plugins.Where(s => s.Key.EndsWith(".zig", StringComparison.Ordinal) && !IsBuildFile(s.Key)).ToList();
var contracts = sources.Where(s => s.Key.StartsWith("src/c/", StringComparison.Ordinal)).ToList();
var headers = sources.Where(s => s.Key.StartsWith("src/", StringComparison.Ordinal) && s.Key.EndsWith(".h", StringComparison.Ordinal)).ToList();
var native = sources.Where(s => s.Key.StartsWith("src/", StringComparison.Ordinal)
    && (s.Key.EndsWith(".h", StringComparison.Ordinal) || s.Key.EndsWith(".c", StringComparison.Ordinal))).ToList();
var managed = sources.Where(s => s.Key.EndsWith(".cs", StringComparison.Ordinal)).ToList();
var factoryHeaders = plugins
    .Where(s => s.Key.EndsWith(".h", StringComparison.Ordinal) && s.Key.Contains("/include/", StringComparison.Ordinal))
    .Where(s => !s.Key.StartsWith("src/zig/common/", StringComparison.Ordinal))
    .ToDictionary(s => s.Key, s => declared.Matches(Regex.Replace(string.Join('\n', s.Value), @"/\*.*?\*/", "", RegexOptions.Singleline))
        .Select(m => m.Groups[1].Value).ToList());
var declaredNames = factoryHeaders.Values.SelectMany(v => v).ToHashSet(StringComparer.Ordinal);

var rules = new List<Rule>
{
    new("a contract directory holds headers and nothing else", 0,
        contracts.Where(s => !s.Key.EndsWith(".h", StringComparison.Ordinal)).Select(s => s.Key)),
    new("no C++ file besides the DLL start-up fixture", 0,
        tracked.Where(p => Regex.IsMatch(p, @"\.(cpp|hpp|cc|hh|cxx)$") && p != cppFixture)),
    new("no InternalsVisibleTo", 0,
        Lines(sources.Where(s => Regex.IsMatch(s.Key, @"\.(cs|csproj|props|targets)$") && !s.Key.StartsWith("scripts/", StringComparison.Ordinal)),
            l => l.Contains("InternalsVisibleTo", StringComparison.Ordinal))),
    new("no assert, abort or panic in engine code; a failure is a ke_error", 0,
        Lines(zig, l => abort.IsMatch(l), outsideTests: true).Concat(Lines(native, l => abort.IsMatch(l)))),
    new("no failure turned into a crash with `catch unreachable` or `orelse unreachable`", 4,
        Lines(zig, l => crashOnFailure.IsMatch(l), outsideTests: true)),
    new("no mutex, condition variable or raw thread in a plugin; the scheduler synchronises", 0,
        Lines(zig, l => threading.IsMatch(l), outsideTests: true)),
    new("no system or task is pinned to a worker", 0,
        Lines(sources.Where(s => Regex.IsMatch(s.Key, @"\.(zig|cs)$") && !s.Key.StartsWith("scripts/", StringComparison.Ordinal)
            && !s.Key.Contains("/scheduler/", StringComparison.Ordinal) && s.Key != "src/zig/runtime/src/runtime.zig"),
            l => pinning.IsMatch(l), outsideTests: true)),
    new("a plugin's root file turns off the per-thread signal stack with std_options", 0,
        tracked.Where(p => p.StartsWith("src/zig/", StringComparison.Ordinal) && IsBuildFile(p))
            .Where(p => sources[p].Any(l => l.Contains(".linkage = .dynamic", StringComparison.Ordinal)))
            .Select(p => (Build: p, Root: LibraryRoot(p, sources[p])))
            .Where(x => x.Root is not null && !(sources.TryGetValue(x.Root, out var root) && root.Any(l => l.Contains("signal_stack_size = null", StringComparison.Ordinal))))
            .Select(x => $"{x.Root}: no std_options with signal_stack_size = null")),
    new("a header has an #ifndef guard, never #pragma once", 0,
        Lines(headers, l => l.TrimStart().StartsWith("#pragma once", StringComparison.Ordinal))),
    new("a contract header declares no export macro", 0,
        Lines(contracts, l => exportMacro.IsMatch(l))),
    new("a contract header declares no plain function", 0,
        Lines(contracts, l => plainFunction.IsMatch(l))),
    new("a plugin exports only what a factory header declares", 0,
        zig.Where(s => !s.Key.StartsWith("src/zig/common/", StringComparison.Ordinal))
            .SelectMany(s => s.Value.Select((l, i) => (s.Key, Line: i + 1, Match: exportFn.Match(l))))
            .Where(x => x.Match.Success && !declaredNames.Contains(x.Match.Groups[1].Value))
            .Select(x => $"{x.Key}:{x.Line}: {x.Match.Groups[1].Value}")),
    new("a factory header declares one function", 0,
        factoryHeaders.Where(h => h.Value.Count > 1).SelectMany(h => h.Value.Skip(1).Select(n => $"{h.Key}: {n}"))),
    new("a parameter bag is named _params, never _desc, _descriptor, _info or _config", 0,
        headers.SelectMany(s => s.Value.SelectMany(l => bagName.Matches(l).Select(m => m.Value))).Distinct(StringComparer.Ordinal)),
    new("no file named after impl", 0,
        tracked.Where(p => p.StartsWith("src/", StringComparison.Ordinal) && implName.IsMatch(Path.GetFileNameWithoutExtension(p)))),
    new("no identifier named after impl", 13,
        Lines(zig.Concat(headers), l => !slashComment.IsMatch(l) && !l.TrimStart().StartsWith("//", StringComparison.Ordinal) && implName.IsMatch(l))),
    new("no comment in Zig besides a doc comment", 0,
        Lines(sources.Where(s => s.Key.EndsWith(".zig", StringComparison.Ordinal)), l => slashComment.IsMatch(l))),
    new("no comment in C besides a doc comment", 10,
        Lines(native, l => slashComment.IsMatch(l) || blockComment.IsMatch(l))),
    new("no comment in C# besides a doc comment", 6,
        Lines(managed, l => slashComment.IsMatch(l))),
    new("a shader in the engine leaves its binding numbers to the compiler", 0,
        Lines(sources.Where(s => s.Key.StartsWith("src/", StringComparison.Ordinal) && s.Key.EndsWith(".slang", StringComparison.Ordinal)), l => shaderBindingNumber.IsMatch(l))),
    new("a plugin binds a shader's parameters by name, never by number", 0,
        Lines(sources.Where(s => s.Key.StartsWith("src/zig/", StringComparison.Ordinal) && s.Key.EndsWith(".zig", StringComparison.Ordinal)), l => bindingNumber.IsMatch(l))),
    new("no comment in a shader", 0,
        Lines(sources.Where(s => s.Key.EndsWith(".slang", StringComparison.Ordinal)), l => slashComment.IsMatch(l))),
    new("no comment in a build manifest, a workflow or the editor config", 0,
        Lines(sources.Where(s => s.Key.EndsWith(".zon", StringComparison.Ordinal)), l => slashComment.IsMatch(l))
            .Concat(Lines(sources.Where(s => s.Key.EndsWith(".yml", StringComparison.Ordinal) || s.Key == ".editorconfig"), l => hashComment.IsMatch(l)))),
};

var failed = 0;
foreach (var rule in rules)
{
    var found = rule.Found.ToList();
    var verdict = found.Count == rule.Ceiling ? "ok" : found.Count > rule.Ceiling ? "MORE" : "STALE";
    Console.WriteLine($"  {found.Count,4} of {rule.Ceiling,4}  {verdict,-5}  {rule.Name}");
    if (found.Count == rule.Ceiling) continue;
    failed++;
    foreach (var f in found.Take(40)) Console.Error.WriteLine($"        {f}");
}

if (failed == 0) return 0;

Console.Error.WriteLine();
Console.Error.WriteLine($"{failed} rule(s) off their ceiling.");
Console.Error.WriteLine("MORE: the listed places break the rule; fix them, the ceiling is not a budget to spend.");
Console.Error.WriteLine("STALE: fewer remain than the ceiling says; lower it in this script so the progress cannot be given back.");
return 1;

static IEnumerable<string> Segments(string path) => path.Split('/');

static bool IsBuildFile(string path) => Path.GetFileName(path) == "build.zig";

static string? LibraryRoot(string buildFile, string[] lines)
{
    var dir = Path.GetDirectoryName(buildFile)!.Replace('\\', '/');
    var root = lines.Select(l => Regex.Match(l, @"\.root_source_file = b\.path\(""([^""]+)""\)")).FirstOrDefault(m => m.Success);
    return root is null ? null : $"{dir}/{root.Groups[1].Value}";
}

static IEnumerable<string> Tracked(string rootDir)
{
    string[] roots = ["src", "scripts", "examples", "tests", "build.zig", "build.zig.zon", ".github", ".editorconfig"];
    string[] skipped = ["obj", "bin", "third_party", ".zig-cache", "zig-out", "zig-pkg", "node_modules"];
    foreach (var root in roots)
    {
        var full = Path.Combine(rootDir, root);
        if (File.Exists(full)) { yield return root; continue; }
        if (!Directory.Exists(full)) continue;
        foreach (var file in Directory.EnumerateFiles(full, "*", SearchOption.AllDirectories))
        {
            var relative = Path.GetRelativePath(rootDir, file).Replace('\\', '/');
            if (relative.Split('/').Any(s => skipped.Contains(s))) continue;
            yield return relative;
        }
    }
}

static IEnumerable<string> Lines(IEnumerable<KeyValuePair<string, string[]>> files, Func<string, bool> breaks, bool outsideTests = false)
{
    foreach (var (path, lines) in files)
    {
        if (outsideTests && Segments(path).Contains("test")) continue;
        for (var i = 0; i < lines.Length; i++)
        {
            if (outsideTests && lines[i].StartsWith("test ", StringComparison.Ordinal)) break;
            if (breaks(lines[i])) yield return $"{path}:{i + 1}: {lines[i].Trim()}";
        }
    }
}

record Rule(string Name, int Ceiling, IEnumerable<string> Found);
