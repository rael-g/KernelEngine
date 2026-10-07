using System.Text;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace Kabic.ClangSharpBackend;

/// <summary>
/// Derives, from the <c>bindings</c> array of the manifest and the headers it names, the ClangSharp job of every binding assembly.
/// </summary>
public static class BindingsPlanner
{
    static readonly Regex Include = new(@"#\s*include\s*<([^>]+)>", RegexOptions.Compiled);
    static readonly Regex TypeName = new(@"\bke_\w+\b", RegexOptions.Compiled);
    static readonly Regex ProjectReference = new(@"ProjectReference\s+Include=""([^""]+)""", RegexOptions.Compiled);

    static readonly Regex[] Declarations =
    [
        new(@"^\s*\}\s*(ke_\w+)\s*;", RegexOptions.Multiline | RegexOptions.Compiled),
        new(@"typedef\s+(?:struct|enum|union)\s+\w*\s*\{[^{}]*\}\s*(ke_\w+)\s*;", RegexOptions.Compiled),
    ];
    static readonly Regex Opaque = new(@"^\s*typedef\s+(?:struct|enum|union)\s+(ke_\w+)\s+\1\s*;", RegexOptions.Multiline | RegexOptions.Compiled);
    static readonly Regex Alias = new(@"^\s*typedef\s+[\w \*]+?\s+(ke_\w+)\s*;", RegexOptions.Multiline | RegexOptions.Compiled);

    public static IReadOnlyList<BindingJob> Plan(string rootDir, string manifestPath)
    {
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        var bindings = manifest["bindings"]?.AsArray()
            ?? throw new InvalidOperationException("the manifest has no 'bindings' array");

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

        HashSet<string> Closure(IEnumerable<string> seeds)
        {
            var seen = new HashSet<string>(StringComparer.Ordinal);
            var queue = new Queue<string>(seeds);
            while (queue.Count > 0)
            {
                var h = queue.Dequeue();
                if (!seen.Add(h) || !File.Exists(h)) continue;
                foreach (Match m in Include.Matches(File.ReadAllText(h)))
                    if (Resolve(m.Groups[1].Value) is { } target) queue.Enqueue(target);
            }
            return seen;
        }

        var declaredIn = new Dictionary<string, string>(StringComparer.Ordinal);
        var aliases = new HashSet<string>(StringComparer.Ordinal);
        var sourceHeaders = Directory.EnumerateFiles(Path.Combine(rootDir, "src"), "*.h", SearchOption.AllDirectories)
            .Where(h => !h.Contains(".zig-cache") && h.Replace('\\', '/').Contains("/kernel_engine/"))
            .Order(StringComparer.Ordinal)
            .ToList();
        var sourceTexts = sourceHeaders.ToDictionary(h => h, File.ReadAllText);
        foreach (var header in sourceHeaders)
            foreach (var rx in Declarations)
                foreach (Match m in rx.Matches(sourceTexts[header]))
                    declaredIn.TryAdd(m.Groups[1].Value, header);
        foreach (var header in sourceHeaders)
            foreach (Match m in Opaque.Matches(sourceTexts[header]))
                declaredIn.TryAdd(m.Groups[1].Value, header);
        foreach (var header in sourceHeaders)
            foreach (Match m in Alias.Matches(sourceTexts[header]))
                if (!declaredIn.ContainsKey(m.Groups[1].Value)) aliases.Add(m.Groups[1].Value);

        var ownHeaders = new Dictionary<string, List<string>>(StringComparer.Ordinal);
        var owner = new Dictionary<string, string>(StringComparer.Ordinal);
        var claimedBy = new Dictionary<string, string>(StringComparer.Ordinal);
        var contested = new List<string>();
        foreach (var b in bindings)
        {
            var name = b!["name"]!.GetValue<string>();
            var hs = b["headers"]!.AsArray().Select(x => Path.Combine(rootDir, x!.GetValue<string>())).ToList();
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
            throw new InvalidOperationException(
                $"{contested.Count} header(s) belong to more than one binding:\n{string.Join('\n', contested.Order())}\n\n"
                + "A type has one owning assembly. Leave the header with the binding that owns it;\n"
                + "the other reaches its types through a remap, and references that project.");

        HashSet<string> Reachable(string projectDir)
        {
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var queue = new Queue<string>();
            foreach (var csproj in Directory.EnumerateFiles(Path.Combine(rootDir, projectDir), "*.csproj")) queue.Enqueue(csproj);
            while (queue.Count > 0)
            {
                var f = queue.Dequeue();
                if (!seen.Add(Path.GetFileNameWithoutExtension(f)) || !File.Exists(f)) continue;
                foreach (Match m in ProjectReference.Matches(File.ReadAllText(f)))
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

        string AngleName(string abs)
        {
            foreach (var root in includeRoots)
                if (abs.StartsWith(root + Path.DirectorySeparatorChar, StringComparison.Ordinal))
                    return Path.GetRelativePath(root, abs).Replace('\\', '/');
            return Path.GetFileName(abs);
        }

        var jobs = new List<BindingJob>();
        var seenProjects = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var b in bindings)
        {
            var name = b!["name"]!.GetValue<string>();
            var project = b["project"]!.GetValue<string>();
            var ns = b["namespace"]!.GetValue<string>();
            var library = b["library"]?.GetValue<string>();
            var extra = (b["additional"]?.AsArray() ?? []).Select(x => x!.GetValue<string>()).ToList();
            var macros = b["macroBindings"]?.GetValue<bool>() ?? false;
            var headers = ownHeaders[name];

            var nativeDir = Path.Combine(rootDir, project, "Native");
            var firstOfProject = seenProjects.Add(project);
            string Rel(string abs) => Path.GetRelativePath(nativeDir, abs).Replace('\\', '/');

            var dirs = Closure(headers)
                .Select(h => includeRoots.FirstOrDefault(r => h.StartsWith(r + Path.DirectorySeparatorChar, StringComparison.Ordinal)))
                .Where(r => r is not null).Select(r => r!)
                .Distinct().OrderBy(Repo, StringComparer.Ordinal).ToList();

            var reach = Reachable(project);

            var traversed = new List<string>(headers);
            var remaps = new List<string>();
            var excludes = new List<string>();
            for (var grew = true; grew;)
            {
                grew = false;
                var declaredHere = declaredIn.Where(kv => traversed.Contains(kv.Value)).Select(kv => kv.Key)
                                             .ToHashSet(StringComparer.Ordinal);
                var referenced = traversed.SelectMany(h => TypeName.Matches(File.ReadAllText(h)).Select(m => m.Value))
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

            string file;
            string? umbrellaBody = null;
            if (headers.Count == 1)
            {
                file = Rel(headers[0]);
            }
            else
            {
                var body = new StringBuilder("#pragma once\n");
                foreach (var h in headers)
                    body.Append("#include <").Append(AngleName(h)).Append(">\n");
                umbrellaBody = body.ToString();
                file = name + ".umbrella.h";
            }

            var config = new List<string> { "multi-file", "latest-codegen" };
            if (firstOfProject) config.Add("generate-helper-types");
            config.Add("generate-file-scoped-namespaces");
            config.Add("exclude-funcs-with-body");
            config.Add("generate-disable-runtime-marshalling");
            if (macros) config.Add("generate-macro-bindings");

            jobs.Add(new BindingJob(
                name, nativeDir, b["output"]!.GetValue<string>(), ns, library,
                dirs.Select(Rel).ToList(), file, umbrellaBody,
                traversed.OrderBy(Repo, StringComparer.Ordinal).Select(Rel).ToList(),
                extra, remaps, excludes.OrderBy(x => x, StringComparer.Ordinal).ToList(), config));
        }

        return jobs;
    }
}
