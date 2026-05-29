namespace KernelEngine.Cli;

/// <summary>
/// Discovers the current project (walking up from the CWD looking for a <c>Project</c> file —
/// same pattern as git) and the engine repo root (next ancestor with a <c>CMakeLists.txt</c> and
/// a <c>src/csharp/</c> directory). Resolves the paths every subcommand needs.
/// </summary>
public sealed class ProjectContext
{
    public string ProjectDirectory { get; }
    public string ProjectFilePath  { get; }
    public string CsprojPath        { get; }
    public string ProgramCsPath     { get; }
    public string EngineRoot        { get; }

    private ProjectContext(string projectDir, string projectFile, string csproj, string programCs, string engineRoot)
    {
        ProjectDirectory = projectDir;
        ProjectFilePath  = projectFile;
        CsprojPath       = csproj;
        ProgramCsPath    = programCs;
        EngineRoot       = engineRoot;
    }

    public static ProjectContext Discover(string? explicitProjectDir = null)
    {
        var startDir = explicitProjectDir ?? Directory.GetCurrentDirectory();
        var projectDir = WalkUp(startDir, dir => File.Exists(Path.Combine(dir, "Project")))
            ?? throw new InvalidOperationException(
                $"No 'Project' file found at {startDir} or any parent directory. " +
                "Run from inside a KernelEngine game project, or pass --project <dir>.");

        var projectFile = Path.Combine(projectDir, "Project");

        var csproj = Directory.GetFiles(projectDir, "*.csproj").FirstOrDefault()
            ?? throw new InvalidOperationException(
                $"No .csproj found in {projectDir}.");

        var programCs = Path.Combine(projectDir, "Program.cs");

        var engineRoot = WalkUp(projectDir, IsEngineRoot)
            ?? throw new InvalidOperationException(
                "Could not locate the engine repo root (looking for a CMakeLists.txt + src/csharp/ ancestor). " +
                "Module discovery in NuGet packages will come in a later slice; for now `ke` only runs against in-repo plugins.");

        return new ProjectContext(projectDir, projectFile, csproj, programCs, engineRoot);
    }

    private static bool IsEngineRoot(string dir) =>
        File.Exists(Path.Combine(dir, "CMakeLists.txt")) &&
        Directory.Exists(Path.Combine(dir, "src", "csharp"));

    private static string? WalkUp(string startDir, Func<string, bool> predicate)
    {
        var dir = new DirectoryInfo(Path.GetFullPath(startDir));
        while (dir != null)
        {
            if (predicate(dir.FullName)) return dir.FullName;
            dir = dir.Parent;
        }
        return null;
    }

    /// <summary>Computes a csproj-friendly relative path from this project to the module's csproj.</summary>
    public string ResolveCsprojReference(ModuleSpec module)
    {
        var absoluteRef = Path.GetFullPath(Path.Combine(EngineRoot, module.CsprojRef));
        return Path.GetRelativePath(ProjectDirectory, absoluteRef);
    }
}
