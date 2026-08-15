#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json.Nodes;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? zigOverride = null;
var only = new List<string>();
for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--zig": zigOverride = args[++i]; break;
        case "--domain": only.Add(args[++i]); break;
    }
}

var manifestPath = Path.Combine(rootDir, "scripts", "api_domains.json");
var domains = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject()["domains"]!.AsArray();

foreach (var dRaw in domains)
{
    var d = dRaw!.AsObject();
    var name = d["name"]!.GetValue<string>();
    if (only.Count > 0 && !only.Contains(name)) continue;

    var apiJson = Path.Combine(rootDir, d["apiJson"]!.GetValue<string>());
    var outDir = Path.Combine(rootDir, d["outDir"]!.GetValue<string>());
    var enumsDir = d["abstractionsOutDir"] is not null
        ? Path.Combine(rootDir, d["abstractionsOutDir"]!.GetValue<string>()) : outDir;

    var extractArgs = new List<string> { "run", "--no-cache", Path.Combine(rootDir, "scripts", "extract_api.cs"), "--",
        "--out", apiJson };
    if (zigOverride is not null) extractArgs.AddRange(["--zig", zigOverride]);
    foreach (var inc in d["includeDirs"]!.AsArray()) extractArgs.AddRange(["-I", Path.Combine(rootDir, inc!.GetValue<string>())]);
    foreach (var aux in d["auxHeaders"]?.AsArray() ?? []) extractArgs.AddRange(["--aux", Path.Combine(rootDir, aux!.GetValue<string>())]);
    foreach (var compose in d["composeHeaders"]?.AsArray() ?? []) extractArgs.AddRange(["--compose", Path.Combine(rootDir, compose!.GetValue<string>())]);
    foreach (var h in d["headers"]!.AsArray()) extractArgs.Add(Path.Combine(rootDir, h!.GetValue<string>()));

    if (!RunDotnet(extractArgs, out var extractErr))
    {
        Console.Error.WriteLine($"[!] {name}: extraction failed:\n{extractErr}");
        return 1;
    }

    var genArgs = new List<string> { "run", "--no-cache", Path.Combine(rootDir, "scripts", "generate_csharp.cs"), "--",
        "--api", apiJson, "--namespace", d["namespace"]!.GetValue<string>(),
        "--native-namespace", d["nativeNamespace"]!.GetValue<string>(),
        "--out", outDir, "--enums-out", enumsDir, "--domain", name };
    foreach (var u in d["usings"]?.AsArray() ?? []) genArgs.AddRange(["--using", u!.GetValue<string>()]);
    if (d["library"] is JsonNode lib) genArgs.AddRange(["--library", lib.GetValue<string>()]);

    if (!RunDotnet(genArgs, out var genErr))
    {
        Console.Error.WriteLine($"[!] {name}: C# generation failed:\n{genErr}");
        return 1;
    }

    if (d["cOut"] is JsonObject cOut)
    {
        var cArgs = new List<string> { "run", "--no-cache", Path.Combine(rootDir, "scripts", "generate_c.cs"), "--",
            "--api", apiJson, "--out", Path.Combine(rootDir, cOut["file"]!.GetValue<string>()),
            "--guard", cOut["guard"]!.GetValue<string>() };
        foreach (var inc in cOut["includes"]!.AsArray()) cArgs.AddRange(["--include", inc!.GetValue<string>()]);

        if (!RunDotnet(cArgs, out var cErr))
        {
            Console.Error.WriteLine($"[!] {name}: C field table generation failed:\n{cErr}");
            return 1;
        }
    }

    Console.WriteLine($"{name}: regenerated");
}

return 0;

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
