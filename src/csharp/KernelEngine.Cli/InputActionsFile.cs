using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Cli;

/// <summary>
/// Edits the project's <c>actions.input</c> file in place. Tomlyn round-trips destroy hand-formatted
/// inline-table bindings and reflow comments, so we use it only to *validate* duplicates — the actual
/// add is a literal text append so the existing content stays byte-identical.
/// </summary>
public sealed class InputActionsFile
{
    private readonly string _absolutePath;
    private readonly string _originalText;
    private readonly TomlTable _model;

    private InputActionsFile(string path, string text, TomlTable model)
    {
        _absolutePath = path;
        _originalText = text;
        _model = model;
    }

    public static InputActionsFile LoadForProject(ProjectContext ctx)
    {
        var manifest = ProjectManifest.Load(ctx.ProjectFilePath);
        var inputRef = manifest.GetConfigValue("input.actions") as string
            ?? throw new InvalidOperationException(
                "Project has no '[input] actions' entry. Add one (e.g. actions = \"res://actions.input\") before declaring input actions.");

        var absolute = ResolveResPath(ctx.ProjectDirectory, inputRef);
        var text = File.Exists(absolute) ? File.ReadAllText(absolute) : "";
        var model = string.IsNullOrEmpty(text) ? new TomlTable() : Toml.ToModel(text);
        return new InputActionsFile(absolute, text, model);
    }

    public string AbsolutePath => _absolutePath;

    public bool HasAction(string name)
    {
        if (!_model.TryGetValue("action", out var actionTbl) || actionTbl is not TomlTable t) return false;
        return t.ContainsKey(name);
    }

    /// <summary>Appends a new <c>[action.&lt;name&gt;]</c> block to the file as raw text — preserves
    /// every prior byte (comments, inline tables, whitespace) untouched.</summary>
    public void AppendAction(string name, string type)
    {
        var nl = _originalText.Contains("\r\n") ? "\r\n" : "\n";
        var separator = _originalText.Length == 0
            ? ""
            : (_originalText.EndsWith(nl) ? nl : nl + nl);

        var block = $"[action.{name}]{nl}type = \"{type}\"{nl}bindings = []{nl}";
        File.WriteAllText(_absolutePath, _originalText + separator + block);
    }

    private static string ResolveResPath(string projectDir, string raw)
    {
        const string prefix = "res://";
        if (!raw.StartsWith(prefix, StringComparison.Ordinal))
            throw new InvalidOperationException(
                $"Input actions path '{raw}' must start with 'res://' (project-relative).");
        return Path.GetFullPath(Path.Combine(projectDir, raw[prefix.Length..]));
    }
}
