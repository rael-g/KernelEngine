namespace Kabic.Bindings;

/// <summary>
/// Orders the plain <c>using</c> directives at the top of a generated file the way the repository's
/// <c>.editorconfig</c> asks: <c>System</c> first, then by name, one blank line between the groups
/// of a first namespace segment.
/// </summary>
public static class UsingBlock
{
    /// <summary>
    /// Returns <paramref name="text"/> with its leading block of plain <c>using</c> directives
    /// ordered and grouped. A file whose leading block holds anything but plain directives and
    /// blank lines, such as a static or an alias directive, is returned unchanged.
    /// </summary>
    public static string Normalize(string text)
    {
        var lines = text.Split('\n');
        var end = 0;
        var names = new List<string>();
        while (end < lines.Length)
        {
            var line = lines[end].TrimEnd('\r');
            if (line.Length == 0) { end++; continue; }
            if (!line.StartsWith("using ") || !line.EndsWith(';')) break;
            var name = line["using ".Length..^1];
            if (name.Contains(' ') || name.Contains('=')) return text;
            names.Add(name);
            end++;
        }
        if (names.Count == 0) return text;

        static string Group(string name) => name.Split('.')[0];
        var ordered = names.Distinct()
            .OrderBy(n => Group(n) == "System" ? 0 : 1)
            .ThenBy(n => n, StringComparer.Ordinal)
            .ToList();

        var block = new List<string>();
        for (var i = 0; i < ordered.Count; i++)
        {
            if (i > 0 && Group(ordered[i]) != Group(ordered[i - 1])) block.Add("");
            block.Add($"using {ordered[i]};");
        }
        block.Add("");
        return string.Join('\n', block.Concat(lines[end..]));
    }

    /// <summary>Normalizes every <c>.cs</c> file under <paramref name="directory"/> in place.</summary>
    public static void NormalizeDirectory(string directory)
    {
        if (!Directory.Exists(directory)) return;
        foreach (var file in Directory.EnumerateFiles(directory, "*.cs", SearchOption.AllDirectories))
        {
            var text = File.ReadAllText(file);
            var normalized = Normalize(text);
            if (normalized != text) File.WriteAllText(file, normalized);
        }
    }
}
