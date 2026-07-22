using System;
using System.Diagnostics;
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
    /// the repository, so fontconfig resolves the platform's default
    /// sans-serif font, distro-layout-agnostic, with a hardcoded fallback list
    /// for platforms without <c>fc-match</c> (Windows, macOS).
    /// </summary>
    /// <exception cref="FileNotFoundException">No candidate font exists.</exception>
    public static string SystemFont
    {
        get
        {
            var viaFontconfig = ResolveViaFontconfig();
            if (viaFontconfig is not null) return viaFontconfig;

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
                "no system TrueType font found via fontconfig or the probed locations");
        }
    }

    private static string? ResolveViaFontconfig()
    {
        try
        {
            var psi = new ProcessStartInfo("fc-match", "--format=%{file} sans-serif")
            {
                RedirectStandardOutput = true,
                UseShellExecute = false,
            };
            using var proc = Process.Start(psi);
            if (proc is null) return null;
            var path = proc.StandardOutput.ReadToEnd().Trim();
            proc.WaitForExit();
            return proc.ExitCode == 0 && File.Exists(path) ? path : null;
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or IOException)
        {
            return null; // fc-match not installed (Windows, macOS, or a minimal container)
        }
    }

    /// <summary>Directory holding the native build output (root build.zig's --prefix).</summary>
    public static string BuildDir => Path.Combine(RepoRoot, "build", "native");

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
