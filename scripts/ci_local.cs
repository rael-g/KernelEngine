#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

const string BaseImage = "ke-ci";
const string WineImage = "ke-ci-wine";
const string ToolsVolume = "ke-ci-tools";
const string PortsVolume = "ke-ci-vcpkg-installed";
const string WindowsPortsVolume = "ke-ci-vcpkg-installed-windows";

var useCache = args.Contains("--cache");
var keep = args.Contains("--keep");
var rebuildImage = args.Contains("--rebuild-image");
var workingTree = args.Contains("--working-tree");
var windows = args.Contains("--windows");
var updateGolden = args.Contains("--update-golden");
var stages = args.Where(a => !a.StartsWith("--")).ToList();
if (updateGolden && stages.Count == 0) stages = ["build", "visual"];
if (windows && stages.Count == 0) stages = ["cross-windows", "test-windows"];
var Image = windows ? WineImage : BaseImage;

if (rebuildImage || !Succeeds("docker", "image", "inspect", BaseImage))
{
    Console.WriteLine("--- building the CI image (Ubuntu 24.04, Zig, .NET, the windowing headers ci.yml installs)");
    if (Run("docker", "build", "--force-rm", "--network", "host", "-t", BaseImage, Path.Combine(rootDir, "scripts", "ci")) != 0) return 1;
}
if (windows && (rebuildImage || !Succeeds("docker", "image", "inspect", WineImage)))
{
    Console.WriteLine("--- building the Windows test image (the CI image plus Wine with a prefix created at build time)");
    if (Run("docker", "build", "--force-rm", "--network", "host", "-t", WineImage, "-f", Path.Combine(rootDir, "scripts", "ci", "Dockerfile.wine"), Path.Combine(rootDir, "scripts", "ci")) != 0) return 1;
}

const string CheckoutPrefix = "ke-ci-";
foreach (var orphan in Directory.EnumerateDirectories(Path.GetTempPath(), CheckoutPrefix + "*"))
{
    var owner = Path.GetFileName(orphan)[CheckoutPrefix.Length..].Split('-')[0];
    if (int.TryParse(owner, out var pid) && IsRunning(pid)) continue;
    Console.WriteLine($"--- removing {orphan}, left behind by a run that did not finish");
    Remove(orphan);
}

var checkout = Path.Combine(Path.GetTempPath(), $"{CheckoutPrefix}{Environment.ProcessId}-{Guid.NewGuid().ToString("N")[..8]}");
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
        foreach (var untracked in Output("git", "-C", rootDir, "ls-files", "--others", "--exclude-standard", "-z").Split('\0', StringSplitOptions.RemoveEmptyEntries))
        {
            var destination = Path.Combine(checkout, untracked);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(Path.Combine(rootDir, untracked), destination, overwrite: true);
            if (!OperatingSystem.IsWindows()) File.SetUnixFileMode(destination, File.GetUnixFileMode(Path.Combine(rootDir, untracked)));
        }
    }
    else if (Run("git", "clone", "--no-hardlinks", "--quiet", rootDir, checkout) != 0) return 1;

    var run = new List<string> { "run", "--rm", "--network", "host", "-v", $"{checkout}:/work", "-w", "/work" };
    if (useCache)
    {
        run.AddRange(["-v", $"{ToolsVolume}:/work/build/tools", "-v", $"{PortsVolume}:/work/build/vcpkg-installed"]);
        if (windows) run.AddRange(["-v", $"{WindowsPortsVolume}:/work/build/vcpkg-installed-x64-windows-zig"]);
    }
    run.AddRange([Image, "dotnet", "run", "scripts/verify.cs", "--", .. stages, .. updateGolden ? ["--update"] : Array.Empty<string>()]);

    Console.WriteLine($"--- running scripts/verify.cs {string.Join(' ', stages)} the way ci.yml does, on Linux"
        + (useCache ? " (vcpkg caches kept between runs)" : " (cold, no caches)"));
    if (windows) Console.WriteLine("    Windows target cross-built on Linux; its tests run under Wine inside the container, never against the host's.");
    else Console.WriteLine("    The Windows leg of the matrix is not simulated here.");
    var exit = Run("docker", [.. run]);
    if (exit == 0 && updateGolden)
    {
        foreach (var file in Directory.EnumerateFiles(Path.Combine(checkout, "golden"), "*", SearchOption.AllDirectories))
        {
            var destination = Path.Combine(rootDir, Path.GetRelativePath(checkout, file));
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(file, destination, overwrite: true);
            Console.WriteLine($"--- {Path.GetRelativePath(rootDir, destination)} recorded");
        }
    }
    return exit;
}
finally
{
    if (keep) Console.WriteLine($"--- kept {checkout}");
    else if (Directory.Exists(checkout)) Remove(checkout);
}

void Remove(string directory)
{
    Run("docker", "run", "--rm", "--network", "host", "-v", $"{directory}:/work", BaseImage, "sh", "-c", "rm -rf /work/* /work/.[!.]*");
    Directory.Delete(directory, recursive: true);
}

static bool IsRunning(int pid)
{
    try { using var process = Process.GetProcessById(pid); return !process.HasExited; }
    catch (ArgumentException) { return false; }
}

static int Run(string command, params string[] arguments)
{
    var info = new ProcessStartInfo(command);
    foreach (var a in arguments) info.ArgumentList.Add(a);
    using var process = Process.Start(info)!;
    process.WaitForExit();
    return process.ExitCode;
}

static string Output(string command, params string[] arguments)
{
    var info = new ProcessStartInfo(command) { RedirectStandardOutput = true };
    foreach (var a in arguments) info.ArgumentList.Add(a);
    using var process = Process.Start(info)!;
    var text = process.StandardOutput.ReadToEnd();
    process.WaitForExit();
    return text;
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
