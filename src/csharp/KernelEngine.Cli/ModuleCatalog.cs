namespace KernelEngine.Cli;

/// <summary>
/// Indexes every <c>.ke-module</c> file the CLI can see, keyed by module id. Discovery walks the
/// engine repo's <c>src/csharp/*/Modules/*.ke-module</c>. NuGet packages will later add a second
/// discovery path (something like <c>$tool-state/packages/*/tools/ke-modules/*.ke-module</c>).
/// </summary>
public sealed class ModuleCatalog
{
    private readonly Dictionary<string, ModuleSpec> _byId;

    public IReadOnlyDictionary<string, ModuleSpec> All => _byId;

    public ModuleCatalog(IEnumerable<ModuleSpec> modules)
    {
        _byId = new Dictionary<string, ModuleSpec>(StringComparer.Ordinal);
        foreach (var m in modules)
        {
            if (_byId.TryGetValue(m.Id, out var existing))
                throw new InvalidDataException(
                    $"Duplicate module id '{m.Id}' — declared in both {existing.SourcePath} and {m.SourcePath}.");
            _byId.Add(m.Id, m);
        }
    }

    public bool TryGet(string id, out ModuleSpec spec) => _byId.TryGetValue(id, out spec!);

    public ModuleSpec Get(string id) =>
        _byId.TryGetValue(id, out var spec)
            ? spec
            : throw new KeyNotFoundException(
                $"Module '{id}' is not in the catalog. Run 'ke list modules' to see what's available.");

    /// <summary>
    /// Discovers every <c>.ke-module</c> file under <paramref name="engineRoot"/>'s standard
    /// in-repo plugin layout (<c>src/csharp/&lt;Project&gt;/Modules/*.ke-module</c>).
    /// </summary>
    public static ModuleCatalog DiscoverInEngineRepo(string engineRoot)
    {
        var pluginsRoot = Path.Combine(engineRoot, "src", "csharp");
        if (!Directory.Exists(pluginsRoot))
            return new ModuleCatalog(Array.Empty<ModuleSpec>());

        var modules = Directory
            .EnumerateDirectories(pluginsRoot)
            .Select(d => Path.Combine(d, "Modules"))
            .Where(Directory.Exists)
            .SelectMany(d => Directory.EnumerateFiles(d, "*.ke-module", SearchOption.TopDirectoryOnly))
            .Select(ModuleSpec.FromFile);

        return new ModuleCatalog(modules);
    }
}
