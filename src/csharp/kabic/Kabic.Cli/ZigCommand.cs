using System.Text.Json.Nodes;
using Kabic;
using Kabic.Zig;

namespace Kabic.Cli;

internal static class ZigCommand
{
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
            Console.Error.WriteLine("usage: kabic zig --domains <api_domains.json> "
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
        var classified = Classifier.Classify(model, providers.ToHashSet(), [], Convention.KernelEngine);
        var text = ZigBackend.Render(model, classified, Convention.KernelEngine, foreign);

        Directory.CreateDirectory(outDir);
        var outPath = Path.Combine(outDir, $"{domain}.zig");
        File.WriteAllText(outPath, text);

        Console.WriteLine($"wrote {classified.Providers.Count} projection(s) to {outPath}");
        return 0;
    }
}
