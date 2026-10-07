using System.Text.Json.Nodes;

namespace Kabic.Cli.Checks;

internal static class ReconstructionCheck
{
    public static int Execute(Options options)
    {
        var rootDir = options.Root;
        var args = options.Raw;
        // Regenerates every kabic-owned artifact into a throwaway root and compares it with
        // the one in the tree. This is the gate the drift checks cannot be: they ask whether
        // the committed output matches the current headers, which a hand edit that happens to
        // agree would also pass. This asks the harder question — can the command produce the
        // tree from nothing — and a file the command no longer knows how to make shows up as
        // missing rather than as silence.



        var shadow = Path.Combine(Path.GetTempPath(), "ke-reconstruction-" + Guid.NewGuid().ToString("N")[..8]);
        Console.WriteLine("Rebuilding every generated artifact from the headers alone...");

        try
        {
            var regenerated = GenerateCommand.Run(options with { Into = shadow });
            if (regenerated != 0)
            {
                Console.Error.WriteLine("[!] regeneration failed");
                return 1;
            }

            var differing = new List<string>();
            var missing = new List<string>();
            var produced = 0;

            foreach (var made in Directory.EnumerateFiles(shadow, "*", SearchOption.AllDirectories))
            {
                produced++;
                var relative = Path.GetRelativePath(shadow, made);
                var committed = Path.Combine(rootDir, relative);
                if (!File.Exists(committed)) { missing.Add(relative); continue; }
                if (!File.ReadAllBytes(made).AsSpan().SequenceEqual(File.ReadAllBytes(committed)))
                    differing.Add(relative);
            }

            foreach (var m in missing) Console.Error.WriteLine($"  produced but absent from the tree: {m}");
            foreach (var d in differing) Console.Error.WriteLine($"  differs from what the headers produce: {d}");

            if (missing.Count > 0 || differing.Count > 0)
            {
                Console.Error.WriteLine(
                    $"\n{missing.Count + differing.Count} of {produced} artifact(s) do not match a clean rebuild.\n"
                    + "Run 'kabic generate' and commit the result.");
                return 1;
            }

            Console.WriteLine($"All {produced} generated artifact(s) rebuild identically from the headers.");
            return 0;
        }
        finally
        {
            if (Directory.Exists(shadow)) Directory.Delete(shadow, recursive: true);
        }
    }
}
