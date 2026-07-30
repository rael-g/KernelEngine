#!/usr/bin/env dotnet run

// kabic's drift gate: detects drift between the C headers and the ke_api.json-driven generated
// C# for every domain in scripts/api_domains.json (ScriptingArchitectureV3
// §8.7: "ke_api.json is an output, regenerated from headers"). Run after
// editing any migrated domain's headers to catch a forgotten
// `dotnet run scripts/extract_api.cs` + `generate_csharp.cs`.
//
// Deliberately content-based, not mtime-based (see scripts/check_bindings_drift.cs,
// which predates this and compares timestamps): a fresh checkout, a rebase, or
// any operation that touches file times without touching content produces a
// false positive or negative under mtime comparison. Regenerating into a temp
// directory and diffing bytes has neither failure mode, and regeneration here
// is cheap and fully deterministic.
//
// Usage: dotnet run scripts/check_api_drift.cs [-- --zig <path>]

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? zigOverride = null;
for (var i = 0; i < args.Length; i++)
    if (args[i] == "--zig") zigOverride = args[++i];

var manifestPath = Path.Combine(rootDir, "scripts", "api_domains.json");
var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
var domains = manifest["domains"]!.AsArray();

Console.WriteLine("Checking for ke_api.json drift (headers vs. generated C#)...");

var driftDetected = false;
var tmpRoot = Path.Combine(Path.GetTempPath(), "ke_api_drift_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tmpRoot);

try
{
    foreach (var dRaw in domains)
    {
        var d = dRaw!.AsObject();
        var name = d["name"]!.GetValue<string>();
        var headers = d["headers"]!.AsArray().Select(h => Path.Combine(rootDir, h!.GetValue<string>())).ToList();
        var includeDirs = d["includeDirs"]!.AsArray().Select(i => Path.Combine(rootDir, i!.GetValue<string>())).ToList();
        var committedApiJson = Path.Combine(rootDir, d["apiJson"]!.GetValue<string>());
        var ns = d["namespace"]!.GetValue<string>();
        var nativeNs = d["nativeNamespace"]!.GetValue<string>();
        var committedOutDir = Path.Combine(rootDir, d["outDir"]!.GetValue<string>());
        var committedAbstractionsDir = d["abstractionsOutDir"] is not null
            ? Path.Combine(rootDir, d["abstractionsOutDir"]!.GetValue<string>()) : committedOutDir;
        var usings = d["usings"]?.AsArray().Select(u => u!.GetValue<string>()).ToList() ?? [];

        var tmpApiJson = Path.Combine(tmpRoot, $"{name}.ke_api.json");
        var tmpOutDir = Path.Combine(tmpRoot, name, "out");
        // Only a real, separate location when the manifest names one (e.g. input's
        // enums live in a different project/dir than its vtable wrapper); otherwise
        // enums land in the same dir as everything else, so compare against that.
        var tmpEnumsDir = d["abstractionsOutDir"] is not null ? Path.Combine(tmpRoot, name, "abstractions") : tmpOutDir;

        var extractArgs = new List<string> { "run", Path.Combine(rootDir, "scripts", "extract_api.cs"), "--",
            "--out", tmpApiJson };
        if (zigOverride is not null) extractArgs.AddRange(["--zig", zigOverride]);
        foreach (var inc in includeDirs) extractArgs.AddRange(["-I", inc]);
        extractArgs.AddRange(headers);

        if (!RunDotnet(extractArgs, out var extractErr))
        {
            Console.WriteLine($"[!] {name}: extraction failed:\n{extractErr}");
            driftDetected = true;
            continue;
        }

        if (!FilesEqual(tmpApiJson, committedApiJson))
        {
            Console.WriteLine($"[!] {name}: ke_api.json is out of date "
                + $"(committed: {Path.GetRelativePath(rootDir, committedApiJson)})");
            driftDetected = true;
        }

        var genArgs = new List<string> { "run", Path.Combine(rootDir, "scripts", "generate_csharp.cs"), "--",
            "--api", tmpApiJson, "--namespace", ns, "--native-namespace", nativeNs,
            "--out", tmpOutDir, "--enums-out", tmpEnumsDir };
        foreach (var u in usings) genArgs.AddRange(["--using", u]);

        if (!RunDotnet(genArgs, out var genErr))
        {
            Console.WriteLine($"[!] {name}: generation failed:\n{genErr}");
            driftDetected = true;
            continue;
        }

        if (!DirsEqual(tmpOutDir, committedOutDir) || !DirsEqual(tmpEnumsDir, committedAbstractionsDir))
        {
            Console.WriteLine($"[!] {name}: generated C# is out of date "
                + $"(committed: {Path.GetRelativePath(rootDir, committedOutDir)})");
            driftDetected = true;
        }
    }
}
finally
{
    Directory.Delete(tmpRoot, recursive: true);
}

if (driftDetected)
{
    Console.WriteLine("\nDrift detected. Regenerate with:");
    Console.WriteLine("  dotnet run scripts/extract_api.cs -- --out <apiJson> -I <dir>... <header.h>...");
    Console.WriteLine("  dotnet run scripts/generate_csharp.cs -- --api <apiJson> --namespace <NS> "
        + "--native-namespace <NS.Native> --out <dir> --enums-out <dir>");
    return 1;
}

Console.WriteLine("No drift detected.");
return 0;

// ---------------------------------------------------------------------------

static bool RunDotnet(List<string> args, out string stderr)
{
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo("dotnet") { RedirectStandardOutput = true, RedirectStandardError = true },
    };
    foreach (var a in args) process.StartInfo.ArgumentList.Add(a);
    process.Start();
    process.StandardOutput.ReadToEnd();
    stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();
    return process.ExitCode == 0;
}

static bool FilesEqual(string a, string b) =>
    File.Exists(b) && File.ReadAllBytes(a).AsSpan().SequenceEqual(File.ReadAllBytes(b));

static bool DirsEqual(string a, string b)
{
    // Neither side has to exist (a domain with no enums never gets an enums dir).
    if (!Directory.Exists(a)) return !Directory.Exists(b) || !Directory.EnumerateFileSystemEntries(b).Any();
    if (!Directory.Exists(b)) return !Directory.EnumerateFileSystemEntries(a).Any();
    var aFiles = Directory.EnumerateFiles(a, "*", SearchOption.AllDirectories)
        .Select(f => Path.GetRelativePath(a, f)).ToHashSet();
    var bFiles = Directory.EnumerateFiles(b, "*", SearchOption.AllDirectories)
        .Select(f => Path.GetRelativePath(b, f)).ToHashSet();
    if (!aFiles.SetEquals(bFiles)) return false;
    return aFiles.All(rel => FilesEqual(Path.Combine(a, rel), Path.Combine(b, rel)));
}
