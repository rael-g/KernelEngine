using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Cli;

/// <summary>
/// Parsed <c>.ke-module</c> file — one entry in the module catalog. Plugin authors ship one of
/// these per module their package exposes (see <c>src/csharp/KernelEngine.Kernel/Modules/*.ke-module</c>
/// for examples). <see cref="ModuleCatalog"/> discovers all of them at command time.
/// </summary>
/// <param name="Id">Globally unique module id ("KernelEngine.Render.Webgpu", "KernelEngine.Logger.Logger", …).</param>
/// <param name="Using">Namespace inserted at top of Program.cs.</param>
/// <param name="Extension">IServiceCollection extension method appended to the services chain.</param>
/// <param name="CsprojRef">Repo-relative path to the csproj this module ships in.</param>
/// <param name="DependsOn">Ids that must come earlier in the topological order.</param>
/// <param name="SourcePath">Absolute path to the .ke-module file (for error messages).</param>
public sealed record ModuleSpec(
    string   Id,
    string   Using,
    string   Extension,
    string   CsprojRef,
    string[] DependsOn,
    string   SourcePath)
{
    public static ModuleSpec FromFile(string path)
    {
        var doc = Toml.ToModel(File.ReadAllText(path));

        string Req(string key)
        {
            if (!doc.TryGetValue(key, out var v) || v is not string s || string.IsNullOrWhiteSpace(s))
                throw new InvalidDataException($"{path}: missing required string field '{key}'.");
            return s;
        }

        string[] Arr(string key)
        {
            if (!doc.TryGetValue(key, out var v)) return Array.Empty<string>();
            if (v is not TomlArray a)
                throw new InvalidDataException($"{path}: field '{key}' must be a string array.");
            return a.Select(x => x as string ?? throw new InvalidDataException(
                                $"{path}: '{key}' contains a non-string entry.")).ToArray();
        }

        return new ModuleSpec(
            Id:         Req("id"),
            Using:      Req("using"),
            Extension:  Req("extension"),
            CsprojRef:  Req("csproj-ref"),
            DependsOn:  Arr("depends-on"),
            SourcePath: path);
    }
}
