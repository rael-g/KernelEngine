#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

const string Image = "ke-ci";
const string ToolsVolume = "ke-ci-tools";
const string PortsVolume = "ke-ci-vcpkg-installed";

var useCache = args.Contains("--cache");
var keep = args.Contains("--keep");
var rebuildImage = args.Contains("--rebuild-image");
var workingTree = args.Contains("--working-tree");
var stages = args.Where(a => !a.StartsWith("--")).ToList();

if (rebuildImage || !Succeeds("docker", "image", "inspect", Image))
{
    Console.WriteLine("--- building the CI image (Ubuntu 24.04, Zig, .NET, the windowing headers ci.yml installs)");
    if (Run("docker", "build", "--network", "host", "-t", Image, Path.Combine(rootDir, "scripts", "ci")) != 0) return 1;
}

var checkout = Path.Combine(Path.GetTempPath(), "ke-ci-" + Guid.NewGuid().ToString("N")[..8]);
try
{
    Console.WriteLine($"--- fresh checkout of {(workingTree ? "the working tree" : "HEAD")} in {checkout}");
    if (workingTree)
    {
        if (Run("git", "-C", rootDir, "clone", "--no-hardlinks", "--quiet", rootDir, checkout) != 0) return 1;
        if (Run("git", "-C", rootDir, "diff", "--binary", "HEAD", "--output=" + Path.Combine(checkout, ".ke-ci.patch")) != 0) return 1;
        if (new FileInfo(Path.Combine(checkout, ".ke-ci.patch")).Length > 0
            && Run("git", "-C", checkout, "apply", ".ke-ci.patch") != 0) return 1;
        File.Delete(Path.Combine(checkout, ".ke-ci.patch"));
    }
    else if (Run("git", "clone", "--no-hardlinks", "--quiet", rootDir, checkout) != 0) return 1;

    var run = new List<string> { "run", "--rm", "--network", "host", "-v", $"{checkout}:/work", "-w", "/work" };
    if (useCache)
    {
        run.AddRange(["-v", $"{ToolsVolume}:/work/build/tools", "-v", $"{PortsVolume}:/work/build/vcpkg-installed"]);
    }
    run.AddRange([Image, "dotnet", "run", "scripts/verify.cs", "--", .. stages]);

    Console.WriteLine($"--- running scripts/verify.cs {string.Join(' ', stages)} the way ci.yml does, on Linux"
        + (useCache ? " (vcpkg caches kept between runs)" : " (cold, no caches)"));
    Console.WriteLine("    The Windows leg of the matrix is not simulated here.");
    return Run("docker", [.. run]);
}
finally
{
    if (!keep && Directory.Exists(checkout)) Run("docker", "run", "--rm", "--network", "host", "-v", $"{checkout}:/work", Image, "sh", "-c", "rm -rf /work/* /work/.[!.]*");
    if (!keep && Directory.Exists(checkout)) Directory.Delete(checkout, recursive: true);
    else if (keep) Console.WriteLine($"--- kept {checkout}");
}

static int Run(string command, params string[] arguments)
{
    var info = new ProcessStartInfo(command);
    foreach (var a in arguments) info.ArgumentList.Add(a);
    using var process = Process.Start(info)!;
    process.WaitForExit();
    return process.ExitCode;
}

static bool Succeeds(string command, params string[] arguments)
{
    var info = new ProcessStartInfo(command) { RedirectStandardOutput = true, RedirectStandardError = true };
    foreach (var a in arguments) info.ArgumentList.Add(a);
    using var process = Process.Start(info)!;
    process.StandardOutput.ReadToEnd();
    process.StandardError.ReadToEnd();
    process.WaitForExit();
    return process.ExitCode == 0;
}
