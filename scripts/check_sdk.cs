#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));
var prefix = Path.Combine(rootDir, "build", "native");
var buildDir = Path.Combine(rootDir, "build", "sdk-check");
var exe = OperatingSystem.IsWindows() ? ".exe" : "";

if (!File.Exists(Path.Combine(prefix, "lib", "cmake", "KernelEngine", "KernelEngineConfig.cmake")))
{
    Console.Error.WriteLine("build/native holds no SDK; run zig build --prefix build/native first");
    return 2;
}
var vcpkg = Directory.Exists(Path.Combine(rootDir, "build", "tools"))
    ? Directory.EnumerateDirectories(Path.Combine(rootDir, "build", "tools"), "vcpkg-*").Select(d => Path.Combine(d, "vcpkg" + exe)).FirstOrDefault(File.Exists)
    : null;
if (vcpkg is null)
{
    Console.Error.WriteLine("no fetched vcpkg under build/tools; run zig build first");
    return 2;
}

(int Code, string Output) Run(string file, IEnumerable<string> args)
{
    var info = new ProcessStartInfo(file) { RedirectStandardOutput = true, RedirectStandardError = true, WorkingDirectory = rootDir };
    foreach (var a in args) info.ArgumentList.Add(a);
    info.Environment["ZIG_LOCAL_CACHE_DIR"] = Path.Combine(rootDir, ".zig-cache");
    info.Environment["ZIG_GLOBAL_CACHE_DIR"] = Path.Combine(rootDir, "build", "zig-global");
    using var process = Process.Start(info)!;
    var stdout = process.StandardOutput.ReadToEndAsync();
    var stderr = process.StandardError.ReadToEndAsync();
    process.WaitForExit();
    return (process.ExitCode, stdout.Result + stderr.Result);
}

string? Fetch(string tool)
{
    var (code, output) = Run(vcpkg, ["fetch", tool, "--x-stderr-status"]);
    var path = output.Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).LastOrDefault(File.Exists);
    if (code != 0 || path is null) Console.Error.WriteLine($"vcpkg could not fetch {tool}:\n{output}");
    return path;
}

var cmake = Fetch("cmake");
var ninja = Fetch("ninja");
if (cmake is null || ninja is null) return 2;

var configure = Run(cmake, [
    "-S", Path.Combine(rootDir, "examples", "c", "pong"), "-B", buildDir, "-G", "Ninja",
    $"-DCMAKE_MAKE_PROGRAM={ninja}", $"-DCMAKE_PREFIX_PATH={prefix}",
    "-DCMAKE_C_COMPILER=zig", "-DCMAKE_C_COMPILER_ARG1=cc"]);
if (configure.Code != 0)
{
    Console.Error.WriteLine($"FAIL configuring the C Pong against the SDK:\n{configure.Output}");
    return 1;
}
var build = Run(cmake, ["--build", buildDir]);
if (build.Code != 0)
{
    Console.Error.WriteLine($"FAIL building the C Pong against the SDK:\n{build.Output}");
    return 1;
}
Console.WriteLine("ok   the C Pong builds with CMake against the installed SDK");
return 0;
