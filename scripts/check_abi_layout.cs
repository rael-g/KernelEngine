#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var snapshotPath = Path.Combine(rootDir, "scripts", "abi_layout.snapshot");

string? zig = null;
var update = false;
for (var i = 0; i < args.Length; i++)
{
    if (args[i] == "--zig") zig = args[++i];
    else if (args[i] == "--update") update = true;
}
zig ??= "zig";

var manifest = JsonNode.Parse(File.ReadAllText(Path.Combine(rootDir, "scripts", "api_domains.json")))!.AsObject();
var tmpRoot = Path.Combine(Path.GetTempPath(), "ke_abi_layout_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tmpRoot);

var snapshot = new StringBuilder();
snapshot.AppendLine("# size, alignment and member offsets of every struct the contract headers declare.");
snapshot.AppendLine("# Regenerate with: dotnet run scripts/check_abi_layout.cs -- --update");

try
{
    foreach (var dRaw in manifest["domains"]!.AsArray())
    {
        var d = dRaw!.AsObject();
        var name = d["name"]!.GetValue<string>();
        var headers = d["headers"]!.AsArray().Select(h => h!.GetValue<string>()).ToList();
        var includeDirs = d["includeDirs"]!.AsArray().Select(i => i!.GetValue<string>()).ToList();
        var api = JsonNode.Parse(File.ReadAllText(Path.Combine(rootDir, d["apiJson"]!.GetValue<string>())))!.AsObject();

        var tu = new StringBuilder();
        tu.AppendLine("#include <stdio.h>");
        tu.AppendLine("#include <stddef.h>");
        foreach (var header in headers)
        {
            var include = includeDirs
                .Select(dir => dir.TrimEnd('/') + "/")
                .Where(prefix => header.StartsWith(prefix, StringComparison.Ordinal))
                .OrderByDescending(prefix => prefix.Length)
                .Select(prefix => header[prefix.Length..])
                .FirstOrDefault();
            if (include is null)
            {
                Console.WriteLine($"[?] {name}: {header} is under none of the domain's include directories");
                return 2;
            }
            tu.AppendLine($"#include <{include}>");
        }

        tu.AppendLine("int main(void) {");
        foreach (var kind in new[] { "structs", "vtables" })
        {
            foreach (var sRaw in api[kind]?.AsArray() ?? [])
            {
                var s = sRaw!.AsObject();
                var type = s["name"]!.GetValue<string>();
                tu.AppendLine($"  printf(\"{type} size=%zu align=%zu\\n\", sizeof({type}), _Alignof({type}));");
                foreach (var fRaw in s["fields"]?.AsArray() ?? [])
                {
                    var field = fRaw!.AsObject()["name"]!.GetValue<string>();
                    tu.AppendLine($"  printf(\"  {field} %zu\\n\", offsetof({type}, {field}));");
                }
                foreach (var slotRaw in s["slots"]?.AsArray() ?? [])
                {
                    var slot = slotRaw!.AsObject()["name"]!.GetValue<string>();
                    tu.AppendLine($"  printf(\"  {slot} %zu\\n\", offsetof({type}, {slot}));");
                }
            }
        }
        tu.AppendLine("  return 0;\n}");

        var src = Path.Combine(tmpRoot, name + ".c");
        var exe = Path.Combine(tmpRoot, name);
        File.WriteAllText(src, tu.ToString());

        var compile = new List<string> { "cc", src, "-o", exe };
        foreach (var inc in includeDirs) { compile.Add("-I"); compile.Add(Path.Combine(rootDir, inc)); }
        if (!Run(zig, compile, out _, out var compileErr))
        {
            Console.WriteLine($"[?] {name}: could not compile the layout probe, so nothing was compared:\n{compileErr}");
            return 2;
        }
        if (!Run(exe, [], out var layout, out var runErr))
        {
            Console.WriteLine($"[?] {name}: the layout probe did not run:\n{runErr}");
            return 2;
        }

        snapshot.AppendLine();
        snapshot.AppendLine($"[{name}]");
        snapshot.Append(layout);
    }
}
finally
{
    Directory.Delete(tmpRoot, recursive: true);
}

var fresh = snapshot.ToString().Replace("\r\n", "\n");
if (update)
{
    File.WriteAllText(snapshotPath, fresh);
    Console.WriteLine($"wrote {Path.GetRelativePath(rootDir, snapshotPath)}");
    return 0;
}

if (!File.Exists(snapshotPath))
{
    Console.WriteLine("scripts/abi_layout.snapshot does not exist; create it with: dotnet run scripts/check_abi_layout.cs -- --update");
    return 1;
}

var committed = File.ReadAllText(snapshotPath).Replace("\r\n", "\n");
if (committed == fresh)
{
    Console.WriteLine("No layout change.");
    return 0;
}

var before = committed.Split('\n');
var after = fresh.Split('\n');
Console.WriteLine("A struct the contract headers declare no longer has the layout the snapshot records:");
PrintChanges("-", before, after);
PrintChanges("+", after, before);
Console.WriteLine("\nIf the change is intended, every plugin and the managed side must be rebuilt against it; then run:");
Console.WriteLine("  dotnet run scripts/check_abi_layout.cs -- --update");
return 1;

static bool Run(string file, List<string> args, out string stdout, out string stderr)
{
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo(file) { RedirectStandardOutput = true, RedirectStandardError = true },
    };
    foreach (var a in args) process.StartInfo.ArgumentList.Add(a);
    process.Start();
    stdout = process.StandardOutput.ReadToEnd();
    stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();
    return process.ExitCode == 0;
}

static void PrintChanges(string mark, string[] from, string[] other)
{
    var kept = new HashSet<string>(other);
    var owner = "";
    foreach (var line in from)
    {
        if (line.Length > 0 && !line.StartsWith(' ') && !line.StartsWith('[') && !line.StartsWith('#')) owner = line;
        if (kept.Contains(line)) continue;
        Console.WriteLine($"  {mark} {(line.StartsWith(' ') ? $"{owner.Split(' ')[0]}:{line}" : line)}");
    }
}
