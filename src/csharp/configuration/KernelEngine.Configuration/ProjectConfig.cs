using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Configuration;

/// <inheritdoc/>
public sealed class ProjectConfig : IProjectConfig
{
    private readonly TomlTable? _root;

    public ProjectConfig(string? tomlPath)
    {
        if (tomlPath is null || !File.Exists(tomlPath)) return;
        var text = File.ReadAllText(tomlPath);
        _root = Toml.ToModel(text);
    }

    public bool IsLoaded => _root is not null;

    public TomlTable? GetSection(string path)
    {
        if (_root is null || string.IsNullOrEmpty(path)) return null;
        TomlTable current = _root;
        foreach (var segment in path.Split('.'))
        {
            if (!current.TryGetValue(segment, out var next) || next is not TomlTable table)
                return null;
            current = table;
        }
        return current;
    }
}
