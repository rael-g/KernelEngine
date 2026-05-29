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
}
