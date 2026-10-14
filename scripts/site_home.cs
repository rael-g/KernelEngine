#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var docsDir = Path.Combine(rootDir, "docs");

var readme = File.ReadAllText(Path.Combine(rootDir, "README.md"));
var home = Regex.Replace(readme, @"\]\(docs/([^)#]*)(#[^)]*)?\)", m =>
{
    var target = m.Groups[1].Value.TrimEnd('/');
    var anchor = m.Groups[2].Value;
    if (target == "README.md") return "](index.md)";
    if (Directory.Exists(Path.Combine(docsDir, target))) return $"]({target}/index.md{anchor})";
    return $"]({target}{anchor})";
});

File.WriteAllText(Path.Combine(docsDir, "index.md"), home);
Console.WriteLine("wrote docs/index.md from README.md");
return 0;
