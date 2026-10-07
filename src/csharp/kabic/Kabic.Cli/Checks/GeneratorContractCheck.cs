using System.Text.RegularExpressions;

namespace Kabic.Cli.Checks;

internal static class GeneratorContractCheck
{
    public static int Execute(Options options)
    {
        var rootDir = options.Root;
        var args = options.Raw;
        var generator = Path.Combine(rootDir, "src", "csharp", "generators", "KernelEngine.SourceGenerators");
        var framework = Path.Combine(rootDir, "src", "csharp", "framework");
        var kabic     = Path.Combine(rootDir, "src", "csharp", "kabic");

        static IEnumerable<string> SourcesUnder(string dir) =>
            Directory.EnumerateFiles(dir, "*.cs", SearchOption.AllDirectories)
                     .Where(p => !p.Replace('\\', '/').Contains("/obj/") && !p.Replace('\\', '/').Contains("/bin/"));

        var declared = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var file in SourcesUnder(framework))
            foreach (Match m in Regex.Matches(File.ReadAllText(file), @"\bclass\s+(\w+Attribute)\b"))
                declared[m.Groups[1].Value] = Path.GetRelativePath(rootDir, file).Replace('\\', '/');

        var matched = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var file in SourcesUnder(generator))
        {
            var text = File.ReadAllText(file);
            foreach (Match m in Regex.Matches(text, @"AttributeClass\?\.Name\s*==\s*""(\w+Attribute)"""))
                matched[m.Groups[1].Value] = Path.GetRelativePath(rootDir, file).Replace('\\', '/');
        }

        var emitted = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var file in SourcesUnder(kabic))
            foreach (Match m in Regex.Matches(File.ReadAllText(file), @"""?\[(\w+)\("))
            {
                var name = m.Groups[1].Value + "Attribute";
                if (declared.ContainsKey(name) || matched.ContainsKey(name))
                    emitted[name] = Path.GetRelativePath(rootDir, file).Replace('\\', '/');
            }

        var breaks = new List<string>();

        foreach (var (name, where) in matched)
            if (!declared.ContainsKey(name))
                breaks.Add($"  {where} matches '{name}', which no class under src/csharp/framework declares");

        foreach (var (name, where) in emitted)
            if (!matched.ContainsKey(name))
                breaks.Add($"  {where} emits [{name[..^"Attribute".Length]}], which the generator never matches");

        if (breaks.Count == 0)
        {
            Console.WriteLine($"The generator, the attributes it matches and the ones kabic emits agree "
                + $"({matched.Count} matched, {emitted.Count} emitted).");
            return 0;
        }

        Console.Error.WriteLine($"{breaks.Count} break(s) in the attribute contract:");
        foreach (var b in breaks.Order()) Console.Error.WriteLine(b);
        Console.Error.WriteLine();
        Console.Error.WriteLine("The generator resolves attributes by name, because an analyzer cannot reference");
        Console.Error.WriteLine("the assembly declaring them. A name that stops agreeing makes the generator skip");
        Console.Error.WriteLine("the node in silence: the type still compiles, and none of its properties bind.");
        return 1;
    }
}
