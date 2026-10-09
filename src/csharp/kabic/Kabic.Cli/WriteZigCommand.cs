using Kabic.Pipeline;
using System.Text.Json.Nodes;
using Kabic;
using Kabic.Zig;
using Kabic.Conventions;

namespace Kabic.Cli;

/// <summary>
/// Implements the command that renders the Zig projection of one domain.
/// </summary>
/// <remarks>
/// Run reads the manifest path, the domain name, the output directory and the providers.
/// Without the first three it writes the usage to the error stream and returns one. The root is
/// the parent of the manifest's directory, and each domain's API file is resolved under it. The
/// named domain must be in the manifest. Every other domain whose API file exists contributes
/// its structs and enums that are not external, and all of its type aliases, to a table of
/// foreign types, each mapped to that domain's Zig file. The named domain's model is then
/// classified against the providers and rendered with that table and the error ABI. The text is
/// written to a file named after the domain in the output directory.
/// </remarks>
internal static class WriteZigCommand
{
    /// <summary>
    /// Writes the Zig projection of the named domain and returns zero. Returns one when a
    /// required option is missing or the named domain is not in the manifest.
    /// </summary>
    public static int Run(IReadOnlyList<string> args)
    {
        string? domainsPath = null, domain = null, outDir = null;
        var providers = new List<string>();

        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case "--domains": domainsPath = args[++i]; break;
                case "--domain": domain = args[++i]; break;
                case "--out-dir": outDir = args[++i]; break;
                case "--provider": providers.Add(args[++i]); break;
            }
        }

        if (domainsPath is null || domain is null || outDir is null)
        {
            Console.Error.WriteLine("usage: kabic write zig --domains <api_domains.json> "
                + "--domain <name> --out-dir <dir> [--provider <ke_vtable>]...");
            return 1;
        }

        var root = Path.GetDirectoryName(Path.GetFullPath(domainsPath))!;
        root = Path.GetFullPath(Path.Combine(root, ".."));

        var domains = JsonNode.Parse(File.ReadAllText(domainsPath))!["domains"]!.AsArray()
            .Select(d => (Name: (string)d!["name"]!, Api: Path.Combine(root, (string)d!["apiJson"]!)))
            .ToList();

        if (!domains.Any(d => d.Name == domain))
        {
            Console.Error.WriteLine($"error: no domain named '{domain}' in {domainsPath}");
            return 1;
        }

        ApiModel ReadModel(string path) => ApiReader.Read(JsonNode.Parse(File.ReadAllText(path))!.AsObject());

        var foreign = new Dictionary<string, ForeignType>();
        foreach (var (name, api) in domains)
        {
            if (name == domain || !File.Exists(api)) continue;
            var owner = ReadModel(api);
            foreach (var s in owner.Structs.Where(s => !s.External))
                foreign.TryAdd(s.Name, new ForeignType(name, $"{name}.zig", true));
            foreach (var e in owner.Enums.Where(e => !e.External))
                foreign.TryAdd(e.Name, new ForeignType(name, $"{name}.zig", false));
            foreach (var (alias, _) in owner.TypeAliases)
                foreign.TryAdd(alias, new ForeignType(name, $"{name}.zig", false));
        }

        var model = ReadModel(domains.First(d => d.Name == domain).Api);
        var convention = ConventionLoader.Load(domainsPath);
        var classified = Classifier.Classify(model, providers.ToHashSet(), [], convention);
        var text = ZigWriter.Render(model, classified, convention, foreign,
            Regeneration.ExtractErrorAbi(convention, root, null));

        Directory.CreateDirectory(outDir);
        var outPath = Path.Combine(outDir, $"{domain}.zig");
        File.WriteAllText(outPath, text);

        Console.WriteLine($"wrote {classified.Providers.Count} projection(s) to {outPath}");
        return 0;
    }
}
