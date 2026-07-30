#!/usr/bin/env dotnet run

// Detects when a C header changed but the generated C# bindings were never
// regenerated: compares each header's mtime against its .rsp's Generated/*.cs
// mtimes. Run after editing any kernel_engine/*.h to catch a forgotten
// `dotnet run scripts/generate_bindings.cs`.

using System.Runtime.CompilerServices;

var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var csharpDir = Path.Combine(rootDir, "src", "csharp");

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

Console.WriteLine("Checking for bindings drift (Headers vs Generated C#)...");

var rspFiles = Directory.EnumerateFiles(csharpDir, "*.rsp", SearchOption.AllDirectories)
    .Where(p => !p.Split(Path.DirectorySeparatorChar).Any(part => part is "bin" or "obj"))
    .ToList();

var driftDetected = false;

foreach (var rsp in rspFiles)
{
    var (headers, outDir) = GetRspInfo(rsp);

    if (!Directory.Exists(outDir))
    {
        Console.WriteLine($"[!] {Path.GetRelativePath(rootDir, rsp)}: Output directory not found: {outDir}");
        driftDetected = true;
        continue;
    }

    DateTime newestHeaderTime = DateTime.MinValue;
    string newestHeaderName = "";
    foreach (var h in headers)
    {
        if (!File.Exists(h))
        {
            Console.WriteLine($"[!] {Path.GetRelativePath(rootDir, rsp)}: Header not found: {h}");
            driftDetected = true;
            continue;
        }
        var mtime = File.GetLastWriteTimeUtc(h);
        if (mtime > newestHeaderTime)
        {
            newestHeaderTime = mtime;
            newestHeaderName = h;
        }
    }

    var genFiles = Directory.EnumerateFiles(outDir, "*.cs", SearchOption.AllDirectories).ToList();
    if (genFiles.Count == 0)
    {
        Console.WriteLine($"[!] {Path.GetRelativePath(rootDir, rsp)}: No generated files found in {outDir}");
        driftDetected = true;
        continue;
    }
    var oldestGenTime = genFiles.Min(File.GetLastWriteTimeUtc);

    // 1-second buffer for filesystem precision.
    if (newestHeaderTime > oldestGenTime + TimeSpan.FromSeconds(1))
    {
        var relHeader = Path.GetRelativePath(rootDir, newestHeaderName);
        var relRsp = Path.GetRelativePath(rootDir, rsp);
        Console.WriteLine($"[DRIFT] {relRsp}: Header '{relHeader}' is newer than bindings.");
        driftDetected = true;
    }
}

if (driftDetected)
{
    Console.WriteLine("\n[FAIL] Drift detected! Please run 'dotnet run scripts/generate_bindings.cs' and commit the changes.");
    return 1;
}

Console.WriteLine("[OK] All bindings are up to date.");
return 0;

// Parses an .rsp file to find input headers (--file) and the output directory
// (--output, relative to the .rsp's own folder — same resolution ClangSharp uses).
static (List<string> Headers, string OutputDir) GetRspInfo(string rspPath)
{
    var rspDir = Path.GetDirectoryName(rspPath)!;
    var headers = new List<string>();
    var outputDir = "Generated";

    var lines = File.ReadAllLines(rspPath);
    for (var i = 0; i < lines.Length; i++)
    {
        var line = lines[i].Trim();
        if (line == "--file" && i + 1 < lines.Length)
            headers.Add(Path.GetFullPath(Path.Combine(rspDir, lines[i + 1].Trim())));
        else if (line == "--output" && i + 1 < lines.Length)
            outputDir = lines[i + 1].Trim();
    }

    return (headers, Path.GetFullPath(Path.Combine(rspDir, outputDir)));
}
