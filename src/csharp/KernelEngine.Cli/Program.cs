using System.CommandLine;
using KernelEngine.Cli;

var projectOpt = new Option<string?>("--project") { Description = "Project directory (default: walk up from CWD)." };

var root = new RootCommand("ke — KernelEngine CLI. Manages references, scenes, and project config so users never touch Program.cs / Project files by hand.");
root.Options.Add(projectOpt);

// ── add module <id> ─────────────────────────────────────────────────────────
var addModuleIdArg = new Argument<string>("id") { Description = "Module id from a .ke-module file (e.g. KernelEngine.Render.Bgfx, KernelEngine.Kernel.Logger)." };
var addModuleCmd = new Command("module", "Add a module to the current project.")
{
    addModuleIdArg,
};
addModuleCmd.SetAction(parseResult =>
{
    var id          = parseResult.GetValue(addModuleIdArg)!;
    var projectArg  = parseResult.GetValue(projectOpt);
    return Run(() => Commands.AddModule(id, projectArg));
});

var addCmd = new Command("add", "Add an entity (module, scene, …) to the project.") { addModuleCmd };

// ── remove module <id> ──────────────────────────────────────────────────────
var removeModuleIdArg = new Argument<string>("id") { Description = "Module id to remove." };
var removeModuleCmd = new Command("module", "Remove a module from the current project.")
{
    removeModuleIdArg,
};
removeModuleCmd.SetAction(parseResult =>
{
    var id          = parseResult.GetValue(removeModuleIdArg)!;
    var projectArg  = parseResult.GetValue(projectOpt);
    return Run(() => Commands.RemoveModule(id, projectArg));
});

var removeCmd = new Command("remove", "Remove an entity from the project.") { removeModuleCmd };

// ── list modules ────────────────────────────────────────────────────────────
var listModulesCmd = new Command("modules", "List modules — both active in this project and available in the catalog.");
listModulesCmd.SetAction(parseResult =>
{
    var projectArg = parseResult.GetValue(projectOpt);
    return Run(() => Commands.ListModules(projectArg));
});

var listCmd = new Command("list", "Enumerate entities matching a filter.") { listModulesCmd };

root.Subcommands.Add(addCmd);
root.Subcommands.Add(removeCmd);
root.Subcommands.Add(listCmd);

return await root.Parse(args).InvokeAsync();

static int Run(Action body)
{
    try { body(); return 0; }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"error: {ex.Message}");
        return 1;
    }
}
