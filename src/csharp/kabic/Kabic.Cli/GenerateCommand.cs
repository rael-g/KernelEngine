using Kabic.Conventions;
using Kabic.Pipeline;

namespace Kabic.Cli;

/// <summary>
/// Implements the command that regenerates the committed outputs of the domains from their
/// headers.
/// </summary>
internal static class GenerateCommand
{
    /// <summary>
    /// Regenerates the selected domains, then, when every domain is selected, runs
    /// <paramref name="extensions"/> and writes what they emit. Returns zero when everything was
    /// written, or one at the first extraction, generation or extension failure.
    /// </summary>
    public static int Run(Options options, IReadOnlyList<IKabicExtension> extensions)
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
            if (convention.ResultCodesOut.Length > 0)
            {
                var codesFile = Place(convention.ResultCodesOut);
                Directory.CreateDirectory(Path.GetDirectoryName(codesFile)!);
                File.WriteAllText(codesFile, Generation.ResultCodes(convention));
                Console.WriteLine("result codes: regenerated");
            }

            if (convention.FieldTable is { ManagedOut: { } managedOut, NativeOut: { } nativeOut })
            {
                foreach (var (path, text) in new[] { (managedOut, Generation.ComponentLayout(convention)), (nativeOut, Generation.NativeFieldTable(convention)) })
                {
                    var file = Place(path);
                    Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                    File.WriteAllText(file, text);
                }
                Console.WriteLine("component layout: regenerated");
            }

            IReadOnlyDictionary<string, string> emitted;
            try
            {
                emitted = ExtensionRunner.Run(extensions, ExtensionRunner.Models(specs, apis), convention,
                    options.Manifest, options.Root, options.Zig, Place);
            }
            catch (InvalidOperationException e)
            {
                Console.Error.WriteLine($"[!] extensions failed:\n{e.Message}");
                return 1;
            }
            foreach (var (path, text) in emitted)
            {
                var file = Place(path);
                Directory.CreateDirectory(Path.GetDirectoryName(file)!);
                File.WriteAllText(file, text);
            }
            foreach (var extension in extensions) Console.WriteLine($"{extension.Name}: regenerated");
        }

        return 0;
    }
}
