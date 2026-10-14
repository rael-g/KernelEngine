#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

const int LineCitationCeiling = 103;

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
foreach (var file in Tracked(rootDir))
    foreach (Match m in identifier.Matches(File.ReadAllText(Path.Combine(rootDir, file))))
        declared.Add(m.Value);

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

var toc = File.ReadAllText(Path.Combine(docsDir, "toc.yml"));
var readme = File.ReadAllText(Path.Combine(docsDir, "README.md"));
var listed = pages.Where(p => p is not ("README.md" or "index.md")).ToList();
var notInToc = listed.Where(p => !toc.Contains($"href: {p}", StringComparison.Ordinal)).ToList();
var notInReadme = listed.Where(p => !readme.Contains($"]({p})", StringComparison.Ordinal)).ToList();

var failed = 0;
failed += Report("a map or a guide names only what the sources declare", unknownNames, 0);
failed += Report("a document names a declaration and its file, never a line", lineCitations, LineCitationCeiling);
failed += Report("every document is in docs/toc.yml", notInToc, 0);
failed += Report("every document is in docs/README.md", notInReadme, 0);
return failed == 0 ? 0 : 1;

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
    var info = new ProcessStartInfo("git") { WorkingDirectory = rootDir, RedirectStandardOutput = true };
    foreach (var a in new[] { "ls-files", "src", "examples", "scripts", "build.zig" }) info.ArgumentList.Add(a);
    using var process = Process.Start(info)!;
    var output = process.StandardOutput.ReadToEnd();
    process.WaitForExit();
    return output.Split('\n', StringSplitOptions.RemoveEmptyEntries)
        .Where(p => !p.Contains("/third_party/", StringComparison.Ordinal))
        .Where(p => Regex.IsMatch(p, @"\.(zig|h|c|cs|slang|json|zon|toml)$"))
        .Where(p => File.Exists(Path.Combine(rootDir, p)));
}
