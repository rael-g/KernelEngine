using System.Text.RegularExpressions;

namespace Kabic.Cli.Checks;

internal static class ComponentFieldsCheck
{
    public static int Execute(Options options)
    {
        var rootDir = options.Root;
        var args = options.Raw;
        var excluded = new Dictionary<string, string>
        {
            ["world_transform"] = "written by the hierarchy alone; every field is output, so a default has no meaning",
        };

        var tables = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var header in Directory.EnumerateFiles(Path.Combine(rootDir, "src"), "component_fields.h", SearchOption.AllDirectories))
        {
            if (header.Contains(".zig-cache")) continue;
            foreach (Match m in Regex.Matches(File.ReadAllText(header), @"ke_component_field\s+(ke_\w+)_component_fields\s*\[\s*\]"))
                tables[m.Groups[1].Value + "_component_fields"] = Path.GetRelativePath(rootDir, header).Replace('\\', '/');
        }

        var nameMacros = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var header in Directory.EnumerateFiles(Path.Combine(rootDir, "src"), "*.h", SearchOption.AllDirectories))
        {
            if (header.Contains(".zig-cache")) continue;
            foreach (Match m in Regex.Matches(File.ReadAllText(header), @"#define\s+(KE_COMPONENT_NAME_\w+)\s+""([^""]+)"""))
                nameMacros[m.Groups[1].Value] = m.Groups[2].Value;
        }

        /// The table a component name owns, matched through the struct the table was
        /// generated from: KE_COMPONENT_NAME_UI_QUAD -> "ui_quad" -> ke_ui_quad_component_fields.
        string? TableFor(string spelledName)
        {
            var literal = spelledName.StartsWith("KE_COMPONENT_NAME_", StringComparison.Ordinal)
                ? nameMacros.GetValueOrDefault(spelledName)
                : spelledName;
            if (literal is null) return null;
            var candidate = $"ke_{literal}_component_fields";
            return tables.ContainsKey(candidate) ? candidate : null;
        }

        var callSite = new Regex(
            @"component_register\s*\.\?\s*\(\s*[^,]+,\s*(?<name>c\.KE_COMPONENT_NAME_\w+|""[^""]+"")\s*,(?<rest>[^;]*?)\)\s*;",
            RegexOptions.Singleline);

        var offenders = new List<string>();
        foreach (var source in Directory.EnumerateFiles(Path.Combine(rootDir, "src", "zig"), "*.zig", SearchOption.AllDirectories))
        {
            if (source.Contains(".zig-cache")) continue;
            var text = File.ReadAllText(source);
            var rel = Path.GetRelativePath(rootDir, source).Replace('\\', '/');

            foreach (Match m in callSite.Matches(text))
            {
                var spelled = m.Groups["name"].Value.TrimStart('c', '.').Trim('"');
                var table = TableFor(spelled);
                if (table is null) continue;

                var literal = spelled.StartsWith("KE_COMPONENT_NAME_", StringComparison.Ordinal)
                    ? nameMacros[spelled]
                    : spelled;
                if (excluded.ContainsKey(literal)) continue;
                if (m.Groups["rest"].Value.Contains(table, StringComparison.Ordinal)) continue;

                var line = text.Take(m.Index).Count(ch => ch == '\n') + 1;
                offenders.Add($"  {rel}:{line}  registers '{literal}' without {table} ({tables[table]})");
            }
        }

        var zigSources = Directory.EnumerateFiles(Path.Combine(rootDir, "src", "zig"), "*.zig", SearchOption.AllDirectories)
            .Where(p => !p.Contains(".zig-cache"))
            .Select(File.ReadAllText)
            .ToList();

        var unused = new List<string>();
        foreach (var (table, header) in tables)
        {
            if (zigSources.Any(s => s.Contains(table, StringComparison.Ordinal))) continue;
            unused.Add($"  {table} ({header}) is named by no registration");
        }

        if (offenders.Count == 0 && unused.Count == 0)
        {
            Console.WriteLine($"Every component whose header declares a field table is registered with it ({tables.Count} table(s) checked).");
            return 0;
        }

        if (unused.Count > 0)
        {
            Console.Error.WriteLine($"{unused.Count} generated field table(s) reach no registration:");
            foreach (var u in unused.Order()) Console.Error.WriteLine(u);
            Console.Error.WriteLine();
        }

        if (offenders.Count == 0)
        {
            Console.Error.WriteLine("A table nothing passes is a set of defaults nothing applies. Register the");
            Console.Error.WriteLine("component with it, or stop generating it.");
            return 1;
        }

        Console.Error.WriteLine($"{offenders.Count} registration(s) drop a field table their header declares:");
        foreach (var o in offenders.Order()) Console.Error.WriteLine(o);
        Console.Error.WriteLine();
        Console.Error.WriteLine("A component registered without its table carries no defaults, so every field");
        Console.Error.WriteLine("it declares one for lands zeroed on whoever attaches it. Pass the table, or");
        Console.Error.WriteLine("record the name in this script's exclusion list with the reason it has none.");
        return 1;
    }
}
