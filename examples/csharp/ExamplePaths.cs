using System;
using System.IO;

/// <summary>
/// Locates engine build outputs for the sample programs.
/// </summary>
/// <remarks>
/// Samples sit at varying depths under <c>examples/</c>, so the repository root
/// is found by walking up from the assembly location rather than by counting
/// parent segments — a fixed count silently resolves to the wrong directory for
/// any sample nested one level deeper.
/// </remarks>
internal static class ExamplePaths
{
    /// <summary>Directory holding the shaders compiled by the native build.</summary>
    public static string ShaderDir => Path.Combine(BuildDir, "bin", "shaders");

    /// <summary>
    /// Path to a TrueType font available on this machine. No font ships with
    /// the repository, so the usual system locations are probed in turn.
    /// </summary>
    /// <exception cref="FileNotFoundException">No candidate font exists.</exception>
    public static string SystemFont
    {
        get
        {
            string[] candidates =
            {
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Fonts), "arial.ttf"),
                "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
                "/usr/share/fonts/TTF/DejaVuSans.ttf",
                "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
                "/System/Library/Fonts/Supplemental/Arial.ttf",
            };

            foreach (var candidate in candidates)
            {
                if (File.Exists(candidate)) return candidate;
            }

            throw new FileNotFoundException(
                "no system TrueType font found in the probed locations");
        }
    }

    /// <summary>Directory holding the native build output for this platform.</summary>
    public static string BuildDir => Path.Combine(RepoRoot, "build", BuildFlavor);

    /// <summary>
    /// Name of the per-platform build directory, matching the CMake presets and
    /// the NativeOS value used by NativeDependencies.targets.
    /// </summary>
    private static string BuildFlavor
    {
        get
        {
            if (OperatingSystem.IsWindows()) return "win";
            if (OperatingSystem.IsMacOS()) return "osx";
            return "linux";
        }
    }

    private static string RepoRoot
    {
        get
        {
            var dir = new DirectoryInfo(AppContext.BaseDirectory);
            while (dir is not null)
            {
                if (Directory.Exists(Path.Combine(dir.FullName, "build")) &&
                    Directory.Exists(Path.Combine(dir.FullName, "examples")))
                {
                    return dir.FullName;
                }
                dir = dir.Parent;
            }

            throw new DirectoryNotFoundException(
                $"could not locate the repository root above '{AppContext.BaseDirectory}'; " +
                "run the native build before starting a sample");
        }
    }
}
