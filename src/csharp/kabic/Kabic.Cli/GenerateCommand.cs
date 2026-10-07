using Kabic.Pipeline;

namespace Kabic.Cli;

internal static class GenerateCommand
{
    public static int Run(Options options)
    {
        var specs = DomainSpec.Load(options.Manifest)
            .Where(s => options.Domains.Count == 0 || options.Domains.Contains(s.Name))
            .ToList();

        string Place(string relative) => Path.Combine(options.Into ?? options.Root, relative);

        IReadOnlyDictionary<string, string> apis;
        try
        {
            apis = Regeneration.ExtractAll(specs, options.Root, options.Zig);
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
                Regeneration.GenerateOne(spec, apis[spec.Name], output);
            }
            catch (InvalidOperationException e)
            {
                Console.Error.WriteLine($"[!] {spec.Name}: generation failed:\n{e.Message}");
                return 1;
            }
            Console.WriteLine($"{spec.Name}: regenerated");
        }

        return 0;
    }
}
