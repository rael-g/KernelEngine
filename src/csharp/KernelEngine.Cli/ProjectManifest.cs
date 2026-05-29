using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Cli;

/// <summary>
/// Reads and writes the <c>[ke]</c> section of a Project file — the source of truth for which
/// modules are active in the project. Preserves the rest of the Project file verbatim by editing
/// the parsed <see cref="TomlTable"/> and re-serializing only that section.
/// </summary>
public sealed class ProjectManifest
{
    private readonly string _path;
    private TomlTable _root;

    public string ProjectDirectory => Path.GetDirectoryName(_path)!;

    private ProjectManifest(string path, TomlTable root)
    {
        _path = path;
        _root = root;
    }

    public static ProjectManifest Load(string projectFilePath)
    {
        var text = File.Exists(projectFilePath) ? File.ReadAllText(projectFilePath) : "";
        var root = string.IsNullOrEmpty(text) ? new TomlTable() : Toml.ToModel(text);
        return new ProjectManifest(projectFilePath, root);
    }

    public IReadOnlyList<string> Modules
    {
        get
        {
            if (!_root.TryGetValue("ke", out var ke) || ke is not TomlTable keTbl) return Array.Empty<string>();
            if (!keTbl.TryGetValue("modules", out var raw) || raw is not TomlArray arr) return Array.Empty<string>();
            return arr.Select(x => x as string ?? "").Where(s => !string.IsNullOrEmpty(s)).ToList();
        }
    }

    public bool AddModule(string id)
    {
        var modules = Modules.ToList();
        if (modules.Contains(id, StringComparer.Ordinal)) return false;
        modules.Add(id);
        WriteModules(modules);
        return true;
    }

    public bool RemoveModule(string id)
    {
        var modules = Modules.ToList();
        if (!modules.Remove(id)) return false;
        WriteModules(modules);
        return true;
    }

    private void WriteModules(IReadOnlyList<string> modules)
    {
        if (!_root.TryGetValue("ke", out var ke) || ke is not TomlTable keTbl)
        {
            keTbl = new TomlTable();
            _root["ke"] = keTbl;
        }
        var arr = new TomlArray();
        foreach (var m in modules) arr.Add(m);
        keTbl["modules"] = arr;
    }

    public void Save()
    {
        File.WriteAllText(_path, Toml.FromModel(_root));
    }

    // ── Generic config get/set ───────────────────────────────────────────────
    //
    // Path is dot-separated and addresses nested TOML tables: "runtime.window.width" → the
    // `width` field inside `[runtime.window]`. The leaf is always a scalar (string, long,
    // double, bool). Arrays and inline tables are not addressable by this path syntax yet —
    // dedicated subverbs (`ke add inputbinding`, `ke set render.clear-color [...]`) will
    // handle those when they ship.

    /// <summary>Reads the scalar at <paramref name="dotPath"/>; returns null when missing.</summary>
    public object? GetConfigValue(string dotPath)
    {
        var (parent, leaf) = NavigateRead(dotPath);
        if (parent is null || leaf is null) return null;
        return parent.TryGetValue(leaf, out var value) ? value : null;
    }

    /// <summary>Writes <paramref name="value"/> at <paramref name="dotPath"/>, creating
    /// intermediate tables as needed. Throws when an intermediate segment exists but is not a table.</summary>
    public void SetConfigValue(string dotPath, object value)
    {
        var segments = SplitPath(dotPath);
        var table = _root;
        for (int i = 0; i < segments.Length - 1; i++)
        {
            var seg = segments[i];
            if (!table.TryGetValue(seg, out var child))
            {
                var fresh = new TomlTable();
                table[seg] = fresh;
                table = fresh;
            }
            else if (child is TomlTable t) table = t;
            else throw new InvalidOperationException(
                $"Cannot descend into '{string.Join('.', segments.Take(i + 1))}' — it exists but is a {child?.GetType().Name ?? "null"}, not a table.");
        }
        table[segments[^1]] = value;
    }

    private (TomlTable? parent, string? leaf) NavigateRead(string dotPath)
    {
        var segments = SplitPath(dotPath);
        var table = _root;
        for (int i = 0; i < segments.Length - 1; i++)
        {
            if (!table.TryGetValue(segments[i], out var child) || child is not TomlTable t) return (null, null);
            table = t;
        }
        return (table, segments[^1]);
    }

    private static string[] SplitPath(string dotPath)
    {
        if (string.IsNullOrWhiteSpace(dotPath))
            throw new ArgumentException("Config path must be non-empty (e.g. 'runtime.window.width').", nameof(dotPath));
        return dotPath.Split('.', StringSplitOptions.RemoveEmptyEntries);
    }
}
