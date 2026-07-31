#!/usr/bin/env dotnet run
#:project ../src/csharp/kabic/Kabic.Frontend/Kabic.Frontend.csproj

// Thin CLI shell over kabic's frontend (src/csharp/kabic/Kabic.Frontend). The
// real project is under src/csharp/ alongside every other real C# project in
// this repo; this script is only the `dotnet run scripts/extract_api.cs`
// entry point, argument parsing, and the `zig cc` process invocation (a
// tooling/environment concern, not part of the language-independent parsing
// logic that lives in the project).
//
// Extracts a semantic description (ke_api.json) of one or more public
// headers: enums, plain structs, vtable structs (structs holding
// function-pointer fields), and free functions, together with each slot's
// doc comment and the bracketed [tag] semantics riding inside it — see
// docs/ScriptingArchitectureV3.md §5 for the annotation vocabulary and why
// it lives in doc comments rather than __attribute__((annotate(...))))
// (attributes are silently dropped by clang on function-pointer-field and
// function-typedef parameters — every public slot in this codebase is
// exactly that shape).
//
// ke_api.json is a build artifact: regenerate it from headers, never hand-edit
// it, same rule that already governs src/csharp/*/Native/Generated/.
//
// Usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... [--aux <header.h>]... <header.h>...
//
// --aux names a header included purely so a foreign domain's typedef'd
// primitives resolve (e.g. gpu_device.h's `typedef uint64_t ke_gpu_buffer`,
// needed for ke_render_service's own params) — only its TypedefDecls are
// recorded; its own vtables/enums/functions are somebody else's domain to
// describe and would otherwise show up as unused, unstable noise here.

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Text.Json;
using System.Text.Json.Nodes;
using Kabic.Frontend;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

string? outPath = null;
string? zigOverride = null;
var includeDirs = new List<string>();
var headers = new List<string>();
var auxHeaders = new List<string>();

for (var i = 0; i < args.Length; i++)
{
    switch (args[i])
    {
        case "--out": outPath = args[++i]; break;
        case "--zig": zigOverride = args[++i]; break;
        case "-I": includeDirs.Add(args[++i]); break;
        case "--aux": auxHeaders.Add(args[++i]); break;
        default: headers.Add(args[i]); break;
    }
}

if (outPath is null || headers.Count == 0)
{
    Console.Error.WriteLine("usage: dotnet run scripts/extract_api.cs -- --out <path> [-I <dir>]... "
        + "[--aux <header.h>]... <header.h>...");
    return 1;
}

var zig = ResolveZig(zigOverride);
var headerPaths = headers.Select(Path.GetFullPath).ToList();
var auxHeaderPaths = auxHeaders.Select(Path.GetFullPath).ToList();
var headerNames = headerPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();
var auxHeaderNames = auxHeaderPaths.Select(Path.GetFileName).Where(n => n is not null).Select(n => n!).ToHashSet();

// -- run clang's AST dumper via `zig cc` (zig IS clang; no extra toolchain) --

var tuDir = Path.Combine(Path.GetTempPath(), "ke_extract_api_" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tuDir);
var tuPath = Path.Combine(tuDir, "tu.c");
File.WriteAllLines(tuPath, headerPaths.Concat(auxHeaderPaths).Select(h => $"#include \"{h.Replace('\\', '/')}\""));

string astJson;
try
{
    astJson = RunAstDump(zig, tuPath, includeDirs);
}
finally
{
    Directory.Delete(tuDir, recursive: true);
}

var ast = JsonNode.Parse(astJson)!.AsObject();

// Raw bytes (not decoded text) of every header, because clang reports byte
// offsets and this codebase has non-ASCII box-drawing characters in comments;
// slicing a decoded string silently shifts every offset after the first one.
// Keyed by the same normalized form Extractor.Owns() builds from clang's own
// loc.file, so the lookup matches regardless of how this path was spelled
// on the command line.
var sourceBytes = headerPaths.Concat(auxHeaderPaths).ToDictionary(Path.GetFullPath, File.ReadAllBytes);

var (api, errors) = Extractor.Extract(ast, headerNames, sourceBytes, auxHeaderNames);

if (errors.Count > 0)
{
    foreach (var e in errors) Console.Error.WriteLine($"ERROR: {e}");
    return 1;
}

Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
File.WriteAllText(outPath, api.ToJson().ToJsonString(new JsonSerializerOptions { WriteIndented = true }));

var vtableCount = api.Structs.Count(s => s.IsVtable);
Console.WriteLine($"wrote {outPath}: enums={api.Enums.Count} structs={api.Structs.Count - vtableCount} "
    + $"vtables={vtableCount} functions={api.Functions.Count}");
return 0;

// ---------------------------------------------------------------------------

static string ResolveZig(string? overridePath)
{
    if (overridePath is not null) return overridePath;
    var fromPath = FindOnPath("zig");
    if (fromPath is not null) return fromPath;
    // Matches this project's distrobox dev-container convention (see
    // .distrobox/dev/.bashrc); a build-time-required override still exists via --zig.
    var distrobox = Path.Combine(Environment.GetEnvironmentVariable("HOME") ?? "",
        "zig-x86_64-linux-0.16.0", "zig");
    if (File.Exists(distrobox)) return distrobox;
    throw new InvalidOperationException("zig not found on PATH; pass --zig <path>");
}

static string? FindOnPath(string exe)
{
    var path = Environment.GetEnvironmentVariable("PATH") ?? "";
    foreach (var dir in path.Split(Path.PathSeparator))
    {
        var candidate = Path.Combine(dir, exe);
        if (File.Exists(candidate)) return candidate;
    }
    return null;
}

// `zig cc -Xclang -ast-dump=json -fsyntax-only` reliably emits a complete,
// valid AST on stdout but still exits 1 with a spurious `<tu>:1:1: error:
// FileNotFound` on stderr for the top-level translation unit — a zig-driver
// quirk (observed on zig 0.16.0), not a real failure. Genuine header errors
// (missing include, syntax error) show up as additional, differently-worded
// diagnostics alongside it, so validity is judged by whether stdout parses as
// non-trivial JSON, not by the process exit code.
static string RunAstDump(string zig, string tuPath, List<string> includeDirs)
{
    using var process = new Process
    {
        StartInfo = new ProcessStartInfo(zig)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        },
    };
    foreach (var a in new[] { "cc", "-Xclang", "-ast-dump=json", "-fsyntax-only", "-fparse-all-comments", tuPath })
        process.StartInfo.ArgumentList.Add(a);
    foreach (var d in includeDirs) { process.StartInfo.ArgumentList.Add("-I"); process.StartInfo.ArgumentList.Add(d); }
    process.Start();
    var stdout = process.StandardOutput.ReadToEnd();
    var stderr = process.StandardError.ReadToEnd();
    process.WaitForExit();

    if (stdout.Length < 2 || stdout[0] != '{')
        throw new InvalidOperationException($"zig cc produced no AST:\n{stderr}");

    var realErrors = stderr.Split('\n')
        .Where(l => l.Contains("error:") && !l.Contains($"{Path.GetFileName(tuPath)}:1:1: error: FileNotFound"))
        .ToList();
    if (realErrors.Count > 0)
        throw new InvalidOperationException("header failed to parse:\n" + string.Join('\n', realErrors));

    return stdout;
}
