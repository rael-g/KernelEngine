using System.Text.Json.Nodes;

namespace Kabic.Cli.Checks;

internal static class OutParamsCheck
{
    public static int Execute(Options options)
    {
        var convention = ConventionLoader.Load(options.Manifest);
        var manifest = JsonNode.Parse(File.ReadAllText(options.Manifest))!.AsObject();
        var offenders = new List<string>();

        void Check(string where, string slot, JsonNode? parameters)
        {
            foreach (var p in parameters?.AsArray() ?? [])
            {
                var name = p!["name"]?.GetValue<string>();
                if (name is null || name == convention.ErrorLaneName) continue;
                if (name != "out" && !name.StartsWith(convention.OutParamPrefix, StringComparison.Ordinal)) continue;
                var tags = (p["tags"]?.AsArray() ?? []).Select(t => t!.GetValue<string>().Split(':')[0]);
                if (tags.Contains("out")) continue;
                offenders.Add($"{where}: {slot}({name})");
            }
        }

        foreach (var domain in manifest["domains"]!.AsArray())
        {
            var apiJson = Path.Combine(options.Root, domain!["apiJson"]!.GetValue<string>());
            if (!File.Exists(apiJson)) continue;
            var api = JsonNode.Parse(File.ReadAllText(apiJson))!.AsObject();
            var where = Path.GetRelativePath(options.Root, apiJson).Replace('\\', '/');

            foreach (var key in (string[])["vtables", "structs", "callbacks"])
                foreach (var owner in api[key]?.AsArray() ?? [])
                {
                    var ownerName = owner!["name"]?.GetValue<string>() ?? "?";
                    foreach (var slot in owner["slots"]?.AsArray() ?? [])
                        Check(where, $"{ownerName}.{slot!["name"]}", slot["params"]);
                    Check(where, ownerName, owner["params"]);
                }

            foreach (var fn in api["functions"]?.AsArray() ?? [])
                Check(where, fn!["name"]!.GetValue<string>(), fn["params"]);
        }

        if (offenders.Count == 0)
        {
            Console.WriteLine("Every written-back parameter declares [out].");
            return 0;
        }

        Console.Error.WriteLine($"{offenders.Count} parameter(s) are written back but carry no [out]:");
        foreach (var o in offenders.Order()) Console.Error.WriteLine($"  {o}");
        Console.Error.WriteLine();
        Console.Error.WriteLine($"A {convention.OutParamPrefix}-prefixed parameter without the tag reaches the managed API as a raw");
        Console.Error.WriteLine("pointer the caller has to pin and dereference itself. Tag it in the header's");
        Console.Error.WriteLine("doc block and regenerate, or rename the parameter if it is not written back.");
        return 1;
    }
}
