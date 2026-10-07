using System.Text;

namespace Kabic.ClangSharpBackend;

/// <summary>
/// Everything ClangSharp is told to generate one binding assembly's raw surface. Paths are relative to <see cref="NativeDir"/>, which is also the working directory of the run.
/// </summary>
public sealed record BindingJob(
    string Name,
    string NativeDir,
    string Output,
    string Namespace,
    string? Library,
    IReadOnlyList<string> IncludeDirectories,
    string File,
    string? UmbrellaBody,
    IReadOnlyList<string> Traverse,
    IReadOnlyList<string> Additional,
    IReadOnlyList<string> Remaps,
    IReadOnlyList<string> Excludes,
    IReadOnlyList<string> Config)
{
    public string Print()
    {
        var sb = new StringBuilder();
        void Opt(string flag, params IEnumerable<string> values)
        {
            sb.Append("--").Append(flag).Append('\n');
            foreach (var v in values) sb.Append(v).Append('\n');
        }

        Opt("output", Output);
        Opt("namespace", Namespace);
        if (Library is not null) Opt("libraryPath", Library);
        foreach (var d in IncludeDirectories) Opt("include-directory", d);
        Opt("file", File);
        Opt("traverse", Traverse);
        if (Additional.Count > 0) Opt("additional", Additional);
        Opt("methodClassName", "NativeMethods");
        Opt("prefixStrip", "ke_");
        if (Namespace != "KernelEngine.Common.Native") Opt("with-using", "*=KernelEngine.Common.Native");
        if (Remaps.Count > 0) Opt("remap", Remaps);
        if (Excludes.Count > 0) Opt("exclude", Excludes);
        Opt("config", Config);
        Opt("language", "c++");
        return sb.ToString();
    }
}
