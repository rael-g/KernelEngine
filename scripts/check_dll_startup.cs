#!/usr/bin/env dotnet run

using System.Runtime.CompilerServices;
using System.Text.RegularExpressions;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

var rootRx = new Regex(@"root_source_file\s*=\s*b\.path\(""([^""]+)""\)", RegexOptions.Compiled);
var missing = new List<string>();
var checkedRoots = 0;

foreach (var build in Directory.EnumerateFiles(Path.Combine(rootDir, "src", "zig"), "build.zig", SearchOption.AllDirectories))
{
    var relative = Path.GetRelativePath(rootDir, build).Replace('\\', '/');
    if (relative.Contains("/zig-pkg/") || relative.Contains(".zig-cache")) continue;
    var match = rootRx.Match(File.ReadAllText(build));
    if (!match.Success) continue;
    var root = Path.Combine(Path.GetDirectoryName(build)!, match.Groups[1].Value);
    if (!File.Exists(root)) continue;

    var text = File.ReadAllText(root);
    if (!text.Contains("@import(\"heap\")", StringComparison.Ordinal)) continue;
    checkedRoots++;
    if (!text.Contains("_DllMainCRTStartup", StringComparison.Ordinal))
        missing.Add(Path.GetRelativePath(rootDir, root).Replace('\\', '/'));
}

if (missing.Count == 0)
{
    Console.WriteLine($"Every plugin root that imports heap re-exports _DllMainCRTStartup ({checkedRoots} root(s)).");
    return 0;
}

Console.Error.WriteLine($"{missing.Count} plugin root(s) import heap and do not re-export _DllMainCRTStartup:");
foreach (var m in missing.Order()) Console.Error.WriteLine($"  {m}");
Console.Error.WriteLine();
Console.Error.WriteLine("Add: pub const _DllMainCRTStartup = @import(\"heap\")._DllMainCRTStartup;");
return 1;
