#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

const int LineCitationCeiling = 94;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var docsDir = Path.Combine(rootDir, "docs");

var pages = Directory.EnumerateFiles(docsDir, "*.md", SearchOption.AllDirectories)
    .Select(p => Path.GetRelativePath(docsDir, p).Replace('\\', '/'))
    .Where(p => !p.StartsWith("kanban/", StringComparison.Ordinal))
    .OrderBy(p => p, StringComparer.Ordinal)
    .ToList();

var identifier = new Regex(@"[A-Za-z_][A-Za-z0-9_]*");
var declared = new HashSet<string>(StringComparer.Ordinal);
foreach (var file in Tracked(rootDir).Where(p => Regex.IsMatch(p, @"\.(zig|h|c|cs|slang|json|zon|toml)$")))
    foreach (Match m in identifier.Matches(File.ReadAllText(Path.Combine(rootDir, file))))
        declared.Add(m.Value);

if (declared.Count == 0)
{
    Console.Error.WriteLine("no source file was read; the names the documents cite cannot be checked");
    return 1;
}

var backticked = new Regex(@"`([^`\n]+)`");
var lineCitation = new Regex(@"\.(zig|h|c|cs|slang|json|toml|yml)`?:\d+|\(`:\d+");
var looksLikePath = new Regex(@"[/]|\.(zig|h|c|cs|md|json|toml|slang|yml|zon|targets|props|csproj|slnx)$");

var unknownNames = new List<string>();
var lineCitations = new List<string>();
foreach (var page in pages)
{
    var lines = File.ReadAllLines(Path.Combine(docsDir, page));
    var checksNames = page.StartsWith("architecture/", StringComparison.Ordinal) || page.StartsWith("guides/", StringComparison.Ordinal);
    for (var i = 0; i < lines.Length; i++)
    {
        if (lineCitation.IsMatch(lines[i])) lineCitations.Add($"docs/{page}:{i + 1}");
        if (!checksNames) continue;
        foreach (Match m in backticked.Matches(lines[i]))
        {
            var name = m.Groups[1].Value;
            if (looksLikePath.IsMatch(name)) continue;
            var missing = identifier.Matches(name).Select(x => x.Value).FirstOrDefault(w => w.Length > 2 && !declared.Contains(w));
            if (missing is not null) unknownNames.Add($"docs/{page}:{i + 1}: `{name}` ({missing})");
        }
    }
}

var listed = pages.Where(p => p.Contains('/') && Path.GetFileName(p) != "index.md").ToList();
var notInToc = listed.Where(p => !TocLists(p)).ToList();
var notInIndex = listed.Where(p => !IndexLists(p)).ToList();

var failed = 0;
failed += Report("a map or a guide names only what the sources declare", unknownNames, 0);
failed += Report("a document names a declaration and its file, never a line", lineCitations, LineCitationCeiling);
failed += Report("every document is in the toc.yml of its directory", notInToc, 0);
failed += Report("every document is in the index.md of its directory", notInIndex, 0);
return failed == 0 ? 0 : 1;

bool IndexLists(string page)
{
    var indexPath = Path.Combine(docsDir, Path.GetDirectoryName(page)!, "index.md");
    return File.Exists(indexPath) && File.ReadAllText(indexPath).Contains($"]({Path.GetFileName(page)})", StringComparison.Ordinal);
}

bool TocLists(string page)
{
    var dir = Path.GetDirectoryName(page)!.Replace('\\', '/');
    var tocPath = Path.Combine(docsDir, dir, "toc.yml");
    return File.Exists(tocPath) && File.ReadAllText(tocPath).Contains($"href: {Path.GetFileName(page)}", StringComparison.Ordinal);
}

static int Report(string rule, List<string> found, int ceiling)
{
    var verdict = found.Count == ceiling ? "ok" : found.Count > ceiling ? "MORE" : "STALE";
    Console.WriteLine($"  {found.Count,4} of {ceiling,4}  {verdict,-5}  {rule}");
    if (found.Count == ceiling) return 0;
    foreach (var f in found.Take(40)) Console.Error.WriteLine($"        {f}");
    if (found.Count < ceiling) Console.Error.WriteLine("        fewer remain than the ceiling says; lower it in this script");
    return 1;
}

static IEnumerable<string> Tracked(string rootDir)
{
    string[] roots = ["src", "examples", "scripts", "build.zig"];
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
