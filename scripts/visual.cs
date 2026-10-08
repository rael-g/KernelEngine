#!/usr/bin/env dotnet run

using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.Compression;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;
var rootDir = Path.GetFullPath(Path.Combine(ScriptDir(), ".."));

const string Platform = "linux-lavapipe";
const string SoftwareIcd = "/usr/share/vulkan/icd.d/lvp_icd.json";
string[] scenes = ["c_demo_15"];

var update = args.Contains("--update");
var goldenDir = Path.Combine(rootDir, "golden", Platform);
var outputDir = Path.Combine(rootDir, "build", "visual", Platform);
Directory.CreateDirectory(outputDir);

if (!File.Exists(SoftwareIcd))
{
    Console.Error.WriteLine($"the goldens under golden/{Platform} are drawn by the pinned lavapipe driver, and {SoftwareIcd} is missing; run this inside the ci image (scripts/ci_local.cs)");
    return 1;
}

var failures = 0;
foreach (var scene in scenes)
{
    var actualPath = Path.Combine(outputDir, scene + ".png");
    var goldenPath = Path.Combine(goldenDir, scene + ".png");
    File.Delete(actualPath);

    var exit = Capture(scene, actualPath);
    if (exit != 0 || !File.Exists(actualPath))
    {
        Console.Error.WriteLine($"FAIL {scene}: capture exited {exit}");
        failures++;
        continue;
    }

    if (update)
    {
        Directory.CreateDirectory(goldenDir);
        File.Copy(actualPath, goldenPath, overwrite: true);
        Console.WriteLine($"updated golden/{Platform}/{scene}.png");
        continue;
    }

    if (!File.Exists(goldenPath))
    {
        Console.Error.WriteLine($"FAIL {scene}: no golden/{Platform}/{scene}.png; run with --update to record it");
        failures++;
        continue;
    }

    var actual = Png.Read(actualPath);
    var golden = Png.Read(goldenPath);
    if (actual.Width != golden.Width || actual.Height != golden.Height)
    {
        Console.Error.WriteLine($"FAIL {scene}: {actual.Width}x{actual.Height} against a {golden.Width}x{golden.Height} golden");
        failures++;
        continue;
    }

    var differing = 0;
    var worst = 0;
    for (var i = 0; i < actual.Rgba.Length; i += 4)
    {
        var texel = 0;
        for (var c = 0; c < 4; c++) texel = Math.Max(texel, Math.Abs(actual.Rgba[i + c] - golden.Rgba[i + c]));
        if (texel > 0) differing++;
        worst = Math.Max(worst, texel);
    }
    if (differing > 0)
    {
        Console.Error.WriteLine($"FAIL {scene}: {differing} of {actual.Width * actual.Height} texels differ, by up to {worst}; actual image in {actualPath}");
        failures++;
    }
    else Console.WriteLine($"ok   {scene}");
}
return failures == 0 ? 0 : 1;

int Capture(string scene, string outputPath)
{
    var exe = Path.Combine(rootDir, "build", "native", "bin", OperatingSystem.IsWindows() ? scene + ".exe" : scene);
    var info = new ProcessStartInfo(exe) { WorkingDirectory = rootDir };
    info.ArgumentList.Add(outputPath);
    info.Environment["VK_ICD_FILENAMES"] = SoftwareIcd;
    using var process = Process.Start(info)!;
    process.WaitForExit();
    return process.ExitCode;
}

record Image(int Width, int Height, byte[] Rgba);

static class Png
{
    public static Image Read(string path)
    {
        var bytes = File.ReadAllBytes(path);
        ReadOnlySpan<byte> signature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
        if (!bytes.AsSpan(0, 8).SequenceEqual(signature)) throw new InvalidDataException($"{path} is not a png");

        int width = 0, height = 0;
        using var compressed = new MemoryStream();
        for (var at = 8; at < bytes.Length;)
        {
            var length = BinaryPrimitives.ReadInt32BigEndian(bytes.AsSpan(at));
            var type = System.Text.Encoding.ASCII.GetString(bytes, at + 4, 4);
            var data = bytes.AsSpan(at + 8, length);
            if (type == "IHDR")
            {
                width = BinaryPrimitives.ReadInt32BigEndian(data);
                height = BinaryPrimitives.ReadInt32BigEndian(data[4..]);
                if (data[8] != 8 || data[9] != 6 || data[12] != 0)
                    throw new InvalidDataException($"{path} is not an 8-bit, non-interlaced rgba png");
            }
            else if (type == "IDAT") compressed.Write(data);
            else if (type == "IEND") break;
            at += 12 + length;
        }

        const int Bpp = 4;
        var stride = width * Bpp;
        var raw = new byte[(stride + 1) * height];
        compressed.Position = 0;
        using (var inflate = new ZLibStream(compressed, CompressionMode.Decompress)) inflate.ReadExactly(raw);

        var rgba = new byte[stride * height];
        for (var y = 0; y < height; y++)
        {
            var filter = raw[y * (stride + 1)];
            var src = raw.AsSpan(y * (stride + 1) + 1, stride);
            var row = rgba.AsSpan(y * stride, stride);
            var up = y > 0 ? rgba.AsSpan((y - 1) * stride, stride) : new byte[stride];
            for (var x = 0; x < stride; x++)
            {
                int a = x >= Bpp ? row[x - Bpp] : 0, b = up[x], c = x >= Bpp ? up[x - Bpp] : 0;
                row[x] = (byte)(src[x] + filter switch
                {
                    0 => 0,
                    1 => a,
                    2 => b,
                    3 => (a + b) / 2,
                    4 => Paeth(a, b, c),
                    _ => throw new InvalidDataException($"{path} uses unknown png filter {filter}"),
                });
            }
        }
        return new Image(width, height, rgba);
    }

    static int Paeth(int a, int b, int c)
    {
        var p = a + b - c;
        int pa = Math.Abs(p - a), pb = Math.Abs(p - b), pc = Math.Abs(p - c);
        return pa <= pb && pa <= pc ? a : pb <= pc ? b : c;
    }
}
