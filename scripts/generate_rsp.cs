#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var check   = args.Contains("--check");

var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(rootDir, "scripts", "api_domains.json")))!.AsObject();
var bindings = manifest["bindings"]?.AsArray()
    ?? throw new InvalidOperationException("api_domains.json has no 'bindings' array");

var includeRoots = Directory.EnumerateDirectories(Path.Combine(rootDir, "src"), "kernel_engine", SearchOption.AllDirectories)
    .Select(Path.GetDirectoryName)
    .Where(p => p is not null && !p.Contains(".zig-cache"))
    .Select(p => p!)
    .Distinct()
    .Order(StringComparer.Ordinal)
    .ToList();

string Repo(string abs) => Path.GetRelativePath(rootDir, abs).Replace('\\', '/');

string? Resolve(string included)
{
    foreach (var root in includeRoots)
    {
        var candidate = Path.Combine(root, included.Replace('/', Path.DirectorySeparatorChar));
        if (File.Exists(candidate)) return candidate;
    }
    return null;
}

var includeRx = new Regex(@"#\s*include\s*<([^>]+)>", RegexOptions.Compiled);

HashSet<string> Closure(IEnumerable<string> seeds)
{
    var seen  = new HashSet<string>(StringComparer.Ordinal);
    var queue = new Queue<string>(seeds);
    while (queue.Count > 0)
    {
        var h = queue.Dequeue();
        if (!seen.Add(h) || !File.Exists(h)) continue;
        foreach (Match m in includeRx.Matches(File.ReadAllText(h)))
            if (Resolve(m.Groups[1].Value) is { } target) queue.Enqueue(target);
    }
    return seen;
}

var declRx = new[]
{
    new Regex(@"^\s*\}\s*(ke_\w+)\s*;", RegexOptions.Multiline | RegexOptions.Compiled),
    new Regex(@"typedef\s+(?:struct|enum|union)\s+\w*\s*\{[^{}]*\}\s*(ke_\w+)\s*;", RegexOptions.Compiled),
};

var opaqueRx = new Regex(@"^\s*typedef\s+(?:struct|enum|union)\s+(ke_\w+)\s+\1\s*;", RegexOptions.Multiline | RegexOptions.Compiled);
var aliasRx  = new Regex(@"^\s*typedef\s+[\w \*]+?\s+(ke_\w+)\s*;", RegexOptions.Multiline | RegexOptions.Compiled);

var declaredIn = new Dictionary<string, string>(StringComparer.Ordinal);
var aliases    = new HashSet<string>(StringComparer.Ordinal);
var sourceHeaders = Directory.EnumerateFiles(Path.Combine(rootDir, "src"), "*.h", SearchOption.AllDirectories)
    .Where(h => !h.Contains(".zig-cache") && h.Replace('\\', '/').Contains("/kernel_engine/"))
    .Order(StringComparer.Ordinal)
    .ToList();
var sourceTexts = sourceHeaders.ToDictionary(h => h, File.ReadAllText);
foreach (var header in sourceHeaders)
    foreach (var rx in declRx)
        foreach (Match m in rx.Matches(sourceTexts[header]))
            declaredIn.TryAdd(m.Groups[1].Value, header);
foreach (var header in sourceHeaders)
    foreach (Match m in opaqueRx.Matches(sourceTexts[header]))
        declaredIn.TryAdd(m.Groups[1].Value, header);
foreach (var header in sourceHeaders)
    foreach (Match m in aliasRx.Matches(sourceTexts[header]))
        if (!declaredIn.ContainsKey(m.Groups[1].Value)) aliases.Add(m.Groups[1].Value);

var ownHeaders = new Dictionary<string, List<string>>(StringComparer.Ordinal);
var owner      = new Dictionary<string, string>(StringComparer.Ordinal);
var claimedBy  = new Dictionary<string, string>(StringComparer.Ordinal);
var contested  = new List<string>();
foreach (var b in bindings)
{
    var name = b!["name"]!.GetValue<string>();
    var hs   = (b["headers"]!.AsArray()).Select(x => Path.Combine(rootDir, x!.GetValue<string>())).ToList();
    ownHeaders[name] = hs;
    foreach (var h in hs)
    {
        if (claimedBy.TryGetValue(h, out var first)) contested.Add($"  {Repo(h)} is claimed by {first} and {name}");
        else claimedBy[h] = name;
    }
    foreach (var (type, header) in declaredIn)
        if (hs.Contains(header)) owner[type] = b["namespace"]!.GetValue<string>();
}

if (contested.Count > 0)
{
    Console.Error.WriteLine($"{contested.Count} header(s) belong to more than one binding:");
    foreach (var c in contested.Order()) Console.Error.WriteLine(c);
    Console.Error.WriteLine();
    Console.Error.WriteLine("A type has one owning assembly. Leave the header with the binding that owns it;");
    Console.Error.WriteLine("the other reaches its types through a remap, and references that project.");
    return 1;
}

var typeRx       = new Regex(@"\bke_\w+\b", RegexOptions.Compiled);
var projRefRx    = new Regex(@"ProjectReference\s+Include=""([^""]+)""", RegexOptions.Compiled);

HashSet<string> Reachable(string projectDir)
{
    var seen  = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
    var queue = new Queue<string>();
    foreach (var csproj in Directory.EnumerateFiles(Path.Combine(rootDir, projectDir), "*.csproj")) queue.Enqueue(csproj);
    while (queue.Count > 0)
    {
        var f = queue.Dequeue();
        if (!seen.Add(Path.GetFileNameWithoutExtension(f)) || !File.Exists(f)) continue;
        foreach (Match m in projRefRx.Matches(File.ReadAllText(f)))
        {
            var target = Path.GetFullPath(Path.Combine(Path.GetDirectoryName(f)!, m.Groups[1].Value.Replace('\\', Path.DirectorySeparatorChar)));
            if (File.Exists(target)) queue.Enqueue(target);
        }
    }
    return seen;
}

var assemblyOf = new Dictionary<string, string>(StringComparer.Ordinal);
foreach (var b in bindings)
    assemblyOf[b!["namespace"]!.GetValue<string>()] = Path.GetFileName(b["project"]!.GetValue<string>());
var umbrellas    = new Dictionary<string, string>(StringComparer.Ordinal);

string AngleName(string abs)
{
    foreach (var root in includeRoots)
        if (abs.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
            return Path.GetRelativePath(root, abs).Replace('\\', '/');
    return Path.GetFileName(abs);
}
var written      = new List<string>();
var stale        = new List<string>();
var seenProjects = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

foreach (var b in bindings)
{
    var name    = b!["name"]!.GetValue<string>();
    var project = b["project"]!.GetValue<string>();
    var ns      = b["namespace"]!.GetValue<string>();
    var library = b["library"]?.GetValue<string>();
    var extra   = (b["additional"]?.AsArray() ?? []).Select(x => x!.GetValue<string>()).ToList();
    var macros  = b["macroBindings"]?.GetValue<bool>() ?? false;
    var headers = ownHeaders[name];

    var nativeDir      = Path.Combine(rootDir, project, "Native");
    var firstOfProject = seenProjects.Add(project);
    string Rel(string abs) => Path.GetRelativePath(nativeDir, abs).Replace('\\', '/');

    var dirs = Closure(headers)
        .Select(h => includeRoots.FirstOrDefault(r => h.StartsWith(r + Path.DirectorySeparatorChar, StringComparison.Ordinal)))
        .Where(r => r is not null).Select(r => r!)
        .Distinct().OrderBy(Repo, StringComparer.Ordinal).ToList();

    var reach = Reachable(project);

    var traversed = new List<string>(headers);
    var remaps    = new List<string>();
    var excludes  = new List<string>();
    for (var grew = true; grew; )
    {
        grew = false;
        var declaredHere = declaredIn.Where(kv => traversed.Contains(kv.Value)).Select(kv => kv.Key)
                                     .ToHashSet(StringComparer.Ordinal);
        var referenced   = traversed.SelectMany(h => typeRx.Matches(File.ReadAllText(h)).Select(m => m.Value))
                                    .ToHashSet(StringComparer.Ordinal);
        remaps.Clear();
        excludes.Clear();
        foreach (var type in referenced.OrderBy(x => x, StringComparer.Ordinal))
        {
            if (aliases.Contains(type)) continue;
            var mine = declaredHere.Contains(type);
            if (owner.TryGetValue(type, out var o)
                && assemblyOf.TryGetValue(o, out var asm) && reach.Contains(asm))
            {
                if (o == ns) continue;
                remaps.Add($"{type}={o}.{type}");
                excludes.Add(type);
                continue;
            }
            if (mine) continue;
            if (declaredIn.TryGetValue(type, out var source) && !traversed.Contains(source))
            {
                traversed.Add(source);
                grew = true;
            }
        }
    }

    var sb = new StringBuilder();
    void Opt(string flag, params string[] values)
    {
        sb.Append("--").Append(flag).Append('\n');
        foreach (var v in values) sb.Append(v).Append('\n');
    }

    Opt("output", b["output"]!.GetValue<string>());
    Opt("namespace", ns);
    if (library is not null) Opt("libraryPath", library);
    foreach (var d in dirs) Opt("include-directory", Rel(d));
    if (headers.Count == 1)
    {
        Opt("file", Rel(headers[0]));
    }
    else
    {
        var umbrella = Path.Combine(nativeDir, name + ".umbrella.h");
        var body = new StringBuilder("#pragma once\n");
        foreach (var h in headers)
            body.Append("#include <").Append(AngleName(h)).Append(">\n");
        umbrellas[umbrella] = body.ToString();
        Opt("file", name + ".umbrella.h");
    }
    Opt("traverse", traversed.OrderBy(Repo, StringComparer.Ordinal).Select(Rel).ToArray());
    if (extra.Count > 0) Opt("additional", extra.ToArray());
    Opt("methodClassName", "NativeMethods");
    Opt("prefixStrip", "ke_");
    if (ns != "KernelEngine.Common.Native") Opt("with-using", "*=KernelEngine.Common.Native");
    if (remaps.Count > 0) Opt("remap", remaps.ToArray());
    if (excludes.Count > 0) Opt("exclude", excludes.OrderBy(x => x, StringComparer.Ordinal).ToArray());

    var config = new List<string> { "multi-file", "latest-codegen" };
    if (firstOfProject) config.Add("generate-helper-types");
    config.Add("generate-file-scoped-namespaces");
    config.Add("exclude-funcs-with-body");
    config.Add("generate-disable-runtime-marshalling");
    if (macros) config.Add("generate-macro-bindings");
    Opt("config", config.ToArray());
    Opt("language", "c++");

    var target = Path.Combine(nativeDir, name + ".rsp");
    var text   = sb.ToString();
    var prior  = File.Exists(target) ? File.ReadAllText(target).Replace("\r\n", "\n") : null;
    if (prior == text) continue;
    if (check) { stale.Add(Repo(target)); continue; }

    Directory.CreateDirectory(nativeDir);
    File.WriteAllText(target, text);
    written.Add(Repo(target));
}

foreach (var (path, body) in umbrellas)
{
    var had = File.Exists(path) ? File.ReadAllText(path).Replace("\r\n", "\n") : null;
    if (had == body) continue;
    if (check) { stale.Add(Repo(path)); continue; }
    File.WriteAllText(path, body);
    written.Add(Repo(path));
}

if (check)
{
    if (stale.Count == 0)
    {
        Console.WriteLine($"Every .rsp matches what the headers describe ({bindings.Count} binding(s)).");
        return 0;
    }
    Console.Error.WriteLine($"{stale.Count} .rsp differ(s) from what the headers describe:");
    foreach (var s in stale.Order()) Console.Error.WriteLine($"  {s}");
    Console.Error.WriteLine();
    Console.Error.WriteLine("Run 'dotnet run scripts/generate_rsp.cs' and commit the result.");
    return 1;
}

Console.WriteLine($"wrote {written.Count} .rsp of {bindings.Count}; {declaredIn.Count} types indexed, "
    + $"{owner.Count} of them owned by a binding.");
foreach (var w in written.Order()) Console.WriteLine($"  {w}");
return 0;
