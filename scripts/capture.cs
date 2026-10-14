#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;
using System.Xml.Linq;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

const string Platform = "linux-lavapipe";
const string SoftwareIcd = "/usr/share/vulkan/icd.d/lvp_icd.json";
string[] scenes = ["c_demo_16"];

var update = args.Contains("--update");
var goldenDir = Path.Combine(rootDir, "tests", "visual", "golden", Platform);
var outputDir = Path.Combine(rootDir, "build", "capture", Platform);
var binDir = Path.Combine(rootDir, "build", "native", "bin");
Directory.CreateDirectory(outputDir);

if (!File.Exists(SoftwareIcd))
{
    Console.Error.WriteLine($"the pass lists under tests/visual/golden/{Platform} are recorded on the pinned lavapipe driver, and {SoftwareIcd} is missing; run this inside the ci image (scripts/ci_local.cs)");
    return 1;
}

var renderdocDir = Directory.GetDirectories(Path.Combine(rootDir, "build", "tools"), "renderdoc-*").FirstOrDefault();
var renderdoccmd = renderdocDir is null ? null : Path.Combine(renderdocDir, "bin", "renderdoccmd");
if (renderdoccmd is null || !File.Exists(renderdoccmd))
{
    Console.Error.WriteLine("build/tools holds no RenderDoc; the native build fetches it (zig build)");
    return 1;
}

var failures = 0;
foreach (var scene in scenes)
{
    foreach (var stale in Directory.GetFiles(outputDir, scene + "*")) File.Delete(stale);
    var goldenPath = Path.Combine(goldenDir, scene + ".passes");

    var exit = Run(renderdoccmd, ["capture", "-w", "-d", binDir, "-c", Path.Combine(outputDir, scene),
        Path.Combine(binDir, scene), Path.Combine(outputDir, scene + ".png"), "--renderdoc"]);
    var capture = Directory.GetFiles(outputDir, scene + "*.rdc").FirstOrDefault();
    if (exit != 0 || capture is null)
    {
        Console.Error.WriteLine($"FAIL {scene}: renderdoccmd capture exited {exit} and left {(capture is null ? "no capture" : capture)}");
        failures++;
        continue;
    }

    var xmlPath = Path.ChangeExtension(capture, ".xml");
    exit = Run(renderdoccmd, ["convert", "-f", capture, "-o", xmlPath, "-c", "xml"]);
    if (exit != 0 || !File.Exists(xmlPath))
    {
        Console.Error.WriteLine($"FAIL {scene}: renderdoccmd convert exited {exit}");
        failures++;
        continue;
    }

    var passes = XDocument.Load(xmlPath).Descendants("chunk")
        .Where(chunk => (string?)chunk.Attribute("name") == "vkCmdBeginDebugUtilsLabelEXT")
        .Select(chunk => chunk.Descendants("string").FirstOrDefault(s => (string?)s.Attribute("name") == "pLabelName")?.Value ?? "")
        .Order(StringComparer.Ordinal)
        .ToArray();
    var actualPath = Path.Combine(outputDir, scene + ".passes");
    File.WriteAllText(actualPath, string.Join("\n", passes) + "\n");

    if (update)
    {
        Directory.CreateDirectory(goldenDir);
        File.Copy(actualPath, goldenPath, overwrite: true);
        Console.WriteLine($"updated tests/visual/golden/{Platform}/{scene}.passes");
        continue;
    }

    if (!File.Exists(goldenPath))
    {
        Console.Error.WriteLine($"FAIL {scene}: no tests/visual/golden/{Platform}/{scene}.passes; run with --update to record it");
        failures++;
        continue;
    }

    var golden = File.ReadAllLines(goldenPath);
    if (!golden.SequenceEqual(passes))
    {
        Console.Error.WriteLine($"FAIL {scene}: the captured frame's passes are [{string.Join(", ", passes)}], against [{string.Join(", ", golden)}]; capture in {capture}");
        failures++;
    }
    else Console.WriteLine($"ok   {scene}  {Path.GetRelativePath(rootDir, capture)}");
}
return failures == 0 ? 0 : 1;

int Run(string exe, string[] arguments)
{
    var info = new ProcessStartInfo(exe) { WorkingDirectory = binDir, RedirectStandardOutput = true, RedirectStandardError = true };
    foreach (var argument in arguments) info.ArgumentList.Add(argument);
    info.Environment["VK_ICD_FILENAMES"] = SoftwareIcd;
    var dataDirs = Environment.GetEnvironmentVariable("XDG_DATA_DIRS");
    info.Environment["XDG_DATA_DIRS"] = Path.Combine(renderdocDir!, "share") + ":" + (string.IsNullOrEmpty(dataDirs) ? "/usr/local/share:/usr/share" : dataDirs);
    using var process = Process.Start(info)!;
    var output = process.StandardOutput.ReadToEndAsync();
    var error = process.StandardError.ReadToEndAsync();
    process.WaitForExit();
    if (process.ExitCode != 0) Console.Error.Write(output.Result + error.Result);
    return process.ExitCode;
}
