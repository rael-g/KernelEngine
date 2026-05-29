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

// ── add inputaction <Name> [--type Button|Axis1D|Axis2D] ────────────────────
var addInputActionNameArg = new Argument<string>("name") { Description = "Action name (PascalCase; added as a member of the [GameActions] enum AND as an [action.<Name>] in actions.input)." };
var addInputActionTypeOpt = new Option<string>("--type") { Description = "Action type: Button, Axis1D, or Axis2D.", DefaultValueFactory = _ => "Button" };
var addInputActionCmd = new Command("inputaction", "Declare a new input action: appends to the [GameActions] enum and the actions.input file.")
{
    addInputActionNameArg, addInputActionTypeOpt,
};
addInputActionCmd.SetAction(parseResult =>
{
    var name = parseResult.GetValue(addInputActionNameArg)!;
    var type = parseResult.GetValue(addInputActionTypeOpt)!;
    var projectArg = parseResult.GetValue(projectOpt);
    return Run(() => Commands.AddInputAction(name, type, projectArg));
});

var addCmd = new Command("add", "Add an entity (module, scene, …) to the project.") { addModuleCmd, addInputActionCmd };

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

// ── set config <path> <value> [--type ...] ──────────────────────────────────
var setConfigPathArg  = new Argument<string>("path")  { Description = "Dotted TOML path inside Project (e.g. 'runtime.window.width')." };
var setConfigValueArg = new Argument<string>("value") { Description = "Value as a string; auto-coerced to bool/int/float when it parses." };
var setConfigTypeOpt  = new Option<ScalarParse.ScalarType>("--type") { Description = "Force scalar type (overrides auto-detect).", DefaultValueFactory = _ => ScalarParse.ScalarType.Auto };
var setConfigCmd = new Command("config", "Set a scalar value in the project Project file.")
{
    setConfigPathArg, setConfigValueArg, setConfigTypeOpt,
};
setConfigCmd.SetAction(parseResult =>
{
    var path  = parseResult.GetValue(setConfigPathArg)!;
    var value = parseResult.GetValue(setConfigValueArg)!;
    var type  = parseResult.GetValue(setConfigTypeOpt);
    var projectArg = parseResult.GetValue(projectOpt);
    return Run(() => Commands.SetConfig(path, value, type, projectArg));
});

var setCmd = new Command("set", "Mutate an entity in the project (config, …).") { setConfigCmd };

// ── get config <path> ───────────────────────────────────────────────────────
var getConfigPathArg = new Argument<string>("path") { Description = "Dotted TOML path inside Project." };
var getConfigCmd = new Command("config", "Read a scalar value from the project Project file (exit 2 when missing).")
{
    getConfigPathArg,
};
getConfigCmd.SetAction(parseResult =>
{
    var path = parseResult.GetValue(getConfigPathArg)!;
    var projectArg = parseResult.GetValue(projectOpt);
    return RunCode(() => Commands.GetConfig(path, projectArg));
});

var getCmd = new Command("get", "Read an entity from the project (config, …).") { getConfigCmd };

root.Subcommands.Add(addCmd);
root.Subcommands.Add(removeCmd);
root.Subcommands.Add(listCmd);
root.Subcommands.Add(setCmd);
root.Subcommands.Add(getCmd);

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

static int RunCode(Func<int> body)
{
    try { return body(); }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"error: {ex.Message}");
        return 1;
    }
}
