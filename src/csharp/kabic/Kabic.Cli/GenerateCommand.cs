using Kabic.Pipeline;
using Kabic.Conventions;

namespace Kabic.Cli;

/// <summary>
/// Implements the command that regenerates the committed outputs of the domains from their
/// headers.
/// </summary>
/// <remarks>
/// Run keeps the domains named on the command line, or every domain when none was named, and
/// loads the convention. <c>Regeneration.ExtractAll</c> extracts all of them first, and a
/// failure there stops the command with one. Each domain then has its output paths planned, its
/// API description written, and its outputs generated. Paths are placed under the into
/// directory when one is given, and under the root otherwise. A generation failure names the
/// domain and stops the command with one. When no domain was named, the error-kinds file is
/// written last.
/// </remarks>
internal static class GenerateCommand
{
    /// <summary>
    /// Regenerates the selected domains and returns zero when all of them were written, or one
    /// at the first extraction or generation failure.
    /// </summary>
    public static int Run(Options options)
    {
        var specs = DomainSpec.Load(options.Manifest)
            .Where(s => options.Domains.Count == 0 || options.Domains.Contains(s.Name))
            .ToList();

        var convention = ConventionLoader.Load(options.Manifest);

        string Place(string relative) => Path.Combine(options.Into ?? options.Root, relative);

        IReadOnlyDictionary<string, string> apis;
        try
        {
            apis = Regeneration.ExtractAll(specs, options.Root, options.Zig, convention);
        }
        catch (InvalidOperationException e)
        {
            Console.Error.WriteLine($"[!] extraction failed:\n{e.Message}");
            return 1;
        }

        foreach (var spec in specs)
        {
            try
            {
                var output = Regeneration.Plan(spec, Place);
                Directory.CreateDirectory(Path.GetDirectoryName(output.ApiJson)!);
                File.WriteAllText(output.ApiJson, apis[spec.Name]);
                Regeneration.GenerateOne(spec, apis[spec.Name], output, convention);
            }
            catch (InvalidOperationException e)
            {
                Console.Error.WriteLine($"[!] {spec.Name}: generation failed:\n{e.Message}");
                return 1;
            }
            Console.WriteLine($"{spec.Name}: regenerated");
        }

        if (options.Domains.Count == 0)
        {
            var kindsFile = Place(convention.ErrorKindsOut);
            Directory.CreateDirectory(Path.GetDirectoryName(kindsFile)!);
            File.WriteAllText(kindsFile, Generation.ErrorKinds(convention));
            Console.WriteLine("error kinds: regenerated");
        }

        return 0;
    }
}
