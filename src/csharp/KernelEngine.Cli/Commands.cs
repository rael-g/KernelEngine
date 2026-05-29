namespace KernelEngine.Cli;

/// <summary>
/// Action bodies for each CLI subcommand. Kept thin — every command:
///   1. Resolves the <see cref="ProjectContext"/>.
///   2. Discovers the catalog.
///   3. Mutates manifest + csproj + Program.cs in that order.
///   4. Saves all three.
/// Each step is small enough to read top-to-bottom; this file is the script that wires them.
/// </summary>
public static class Commands
{
    public static void AddModule(string id, string? projectDir)
    {
        var ctx     = ProjectContext.Discover(projectDir);
        var catalog = ModuleCatalog.DiscoverInEngineRepo(ctx.EngineRoot);
        var spec    = catalog.Get(id);

        // Pull every required transitive dep into the manifest too — saves the user the chore
        // of remembering them all and matches what every package manager already does.
        var manifest = ProjectManifest.Load(ctx.ProjectFilePath);
        var newlyAdded = new List<string>();
        AddRecursive(spec, catalog, manifest, newlyAdded);

        var ordered = TopologicalSort.Sort(
            manifest.Modules.Select(catalog.Get), catalog);

        var csproj = CsprojEditor.Load(ctx.CsprojPath);
        foreach (var m in ordered)
        {
            var refPath = ctx.ResolveCsprojReference(m);
            csproj.AddProjectReference(refPath);
        }

        ProgramCsSync.Sync(ctx.ProgramCsPath, ordered);

        manifest.Save();
        csproj.Save();

        Console.WriteLine(newlyAdded.Count switch
        {
            0 => $"Module '{id}' is already in the project. No changes.",
            1 => $"Added module '{id}'.",
            _ => $"Added '{id}' + {newlyAdded.Count - 1} transitive dependencies: {string.Join(", ", newlyAdded.Where(x => x != id))}.",
        });
    }

    public static void RemoveModule(string id, string? projectDir)
    {
        var ctx     = ProjectContext.Discover(projectDir);
        var catalog = ModuleCatalog.DiscoverInEngineRepo(ctx.EngineRoot);
        var spec    = catalog.Get(id);

        var manifest = ProjectManifest.Load(ctx.ProjectFilePath);
        if (!manifest.RemoveModule(id))
        {
            Console.WriteLine($"Module '{id}' was not active. No changes.");
            return;
        }

        // Are there other active modules still shipping in the same csproj? If yes, keep the
        // ProjectReference — only the last hold-out triggers the csproj entry removal.
        var stillNeeded = manifest.Modules
            .Select(catalog.Get)
            .Any(m => string.Equals(m.CsprojRef, spec.CsprojRef, StringComparison.OrdinalIgnoreCase));

        var csproj = CsprojEditor.Load(ctx.CsprojPath);
        if (!stillNeeded) csproj.RemoveProjectReference(ctx.ResolveCsprojReference(spec));

        var ordered = TopologicalSort.Sort(
            manifest.Modules.Select(catalog.Get), catalog);
        ProgramCsSync.Sync(ctx.ProgramCsPath, ordered);

        manifest.Save();
        csproj.Save();

        Console.WriteLine($"Removed module '{id}'.");
    }

    public static void SetConfig(string path, string value, ScalarParse.ScalarType type, string? projectDir)
    {
        var ctx = ProjectContext.Discover(projectDir);
        var manifest = ProjectManifest.Load(ctx.ProjectFilePath);
        var parsed = ScalarParse.Parse(value, type);
        manifest.SetConfigValue(path, parsed);
        manifest.Save();
        Console.WriteLine($"Set {path} = {Format(parsed)}");
    }

    /// <summary>Returns 0 on hit, 2 on miss (script-friendly: lets `if ! ke get …` branch cleanly).</summary>
    public static int GetConfig(string path, string? projectDir)
    {
        var ctx = ProjectContext.Discover(projectDir);
        var manifest = ProjectManifest.Load(ctx.ProjectFilePath);
        var v = manifest.GetConfigValue(path);
        if (v is null) return 2;
        Console.WriteLine(Format(v));
        return 0;
    }

    private static string Format(object value) => value switch
    {
        bool b   => b ? "true" : "false",
        double d => d.ToString("G", System.Globalization.CultureInfo.InvariantCulture),
        long l   => l.ToString(System.Globalization.CultureInfo.InvariantCulture),
        string s => s,
        _        => value.ToString() ?? "",
    };

    public static void ListModules(string? projectDir)
    {
        var ctx     = ProjectContext.Discover(projectDir);
        var catalog = ModuleCatalog.DiscoverInEngineRepo(ctx.EngineRoot);
        var active  = ProjectManifest.Load(ctx.ProjectFilePath).Modules.ToHashSet(StringComparer.Ordinal);

        Console.WriteLine("ACTIVE in this project:");
        foreach (var id in active.OrderBy(x => x, StringComparer.Ordinal))
            Console.WriteLine($"  ✓ {id}");

        Console.WriteLine();
        Console.WriteLine("AVAILABLE in catalog:");
        foreach (var (id, _) in catalog.All.OrderBy(p => p.Key, StringComparer.Ordinal))
        {
            if (active.Contains(id)) continue;
            Console.WriteLine($"    {id}");
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    private static void AddRecursive(ModuleSpec spec, ModuleCatalog catalog, ProjectManifest manifest, List<string> added)
    {
        if (manifest.Modules.Contains(spec.Id, StringComparer.Ordinal)) return;

        foreach (var dep in spec.DependsOn)
        {
            if (catalog.TryGet(dep, out var depSpec))
                AddRecursive(depSpec, catalog, manifest, added);
        }

        if (manifest.AddModule(spec.Id))
            added.Add(spec.Id);
    }
}
