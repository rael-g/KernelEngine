using System.Xml.Linq;

namespace KernelEngine.Cli;

/// <summary>
/// Minimal XML mutator for the project's csproj file. Adds / removes
/// <c>&lt;ProjectReference Include="..." /&gt;</c> entries while preserving everything else
/// (other ItemGroups, PropertyGroups, formatting where possible).
/// </summary>
public sealed class CsprojEditor
{
    private readonly string _path;
    private readonly XDocument _doc;

    private CsprojEditor(string path, XDocument doc) { _path = path; _doc = doc; }

    public static CsprojEditor Load(string path) =>
        new(path, XDocument.Load(path, LoadOptions.PreserveWhitespace));

    /// <summary>
    /// Ensures a &lt;ProjectReference Include="relativePath" /&gt; exists in some ItemGroup.
    /// Returns true when a new entry was added.
    /// </summary>
    public bool AddProjectReference(string relativePath)
    {
        var normalized = NormalizeSeparators(relativePath);
        if (HasProjectReference(normalized)) return false;

        var groupForRefs = FindOrCreateItemGroupForReferences();
        var entry = new XElement("ProjectReference", new XAttribute("Include", normalized));
        // Pretty insert with newline + indent matching the group's existing children.
        if (groupForRefs.HasElements)
        {
            var last = groupForRefs.Elements().Last();
            last.AddAfterSelf(new XText("\n    "), entry);
        }
        else
        {
            groupForRefs.Add(new XText("\n    "), entry, new XText("\n  "));
        }
        return true;
    }

    /// <summary>
    /// Removes the &lt;ProjectReference Include="relativePath" /&gt; if present.
    /// Returns true when an entry was removed.
    /// </summary>
    public bool RemoveProjectReference(string relativePath)
    {
        var normalized = NormalizeSeparators(relativePath);
        var entry = _doc.Descendants("ProjectReference")
            .FirstOrDefault(e => PathsEqual((string?)e.Attribute("Include"), normalized));
        if (entry is null) return false;

        // Drop the entry plus its preceding whitespace so we don't leave a blank line.
        if (entry.PreviousNode is XText leading) leading.Remove();
        entry.Remove();
        return true;
    }

    public bool HasProjectReference(string relativePath)
    {
        var normalized = NormalizeSeparators(relativePath);
        return _doc.Descendants("ProjectReference")
            .Any(e => PathsEqual((string?)e.Attribute("Include"), normalized));
    }

    public void Save() => _doc.Save(_path, SaveOptions.DisableFormatting);

    private XElement FindOrCreateItemGroupForReferences()
    {
        var root = _doc.Root!;
        var ig = root.Elements("ItemGroup")
                     .FirstOrDefault(g => g.Elements("ProjectReference").Any());
        if (ig != null) return ig;

        // Create a dedicated ItemGroup for ProjectReferences. Don't reuse a Content group —
        // mixing concerns in one ItemGroup is visibly ugly and breaks the convention every other
        // csproj in the repo follows.
        var newGroup = new XElement("ItemGroup");
        root.Add(new XText("\n  "), newGroup, new XText("\n"));
        return newGroup;
    }

    private static string NormalizeSeparators(string path) => path.Replace('/', '\\');

    private static bool PathsEqual(string? a, string b) =>
        a != null && string.Equals(NormalizeSeparators(a), NormalizeSeparators(b), StringComparison.OrdinalIgnoreCase);
}
