using Kabic.Cli.Checks;
using Kabic.Pipeline;

namespace Kabic.Cli;

/// <summary>
/// The commands of kabic, for a host to run with the extensions it composes; the host's
/// <c>Main</c> returns what <see cref="Run"/> returns.
/// </summary>
public static class KabicCli
{
    /// <summary>
    /// Runs the command <paramref name="args"/> names, with <paramref name="extensions"/> run by
    /// <c>generate</c> and compared by <c>check drift</c>. Returns 0, 1 on a failure, 2 when the
    /// command could not run or is unknown.
    /// </summary>
    public static int Run(string[] args, IReadOnlyList<IKabicExtension> extensions)
    {
        var checks = new Dictionary<string, Func<Options, int>>
        {
            ["drift"] = o => DriftCommand.Run(o, extensions),
            ["bindings"] = BindingsCommand.CheckDrift,
            ["reconstruction"] = o => ReconstructionCheck.Execute(o, extensions),
            ["out-params"] = OutParamsCheck.Execute,
            ["zig"] = WriteZigCommand.CheckDrift,
        };

        if (args is ["generate", .. var generateArgs])
            return GenerateCommand.Run(Options.Parse(generateArgs), extensions);

        if (args is ["read", .. var readArgs])
            return ReadCommand.Run(readArgs);

        if (args is ["write", "csharp", .. var csharpArgs])
            return WriteCSharpCommand.Run(csharpArgs);

        if (args is ["write", "zig", .. var zigArgs])
            return WriteZigCommand.Run(Options.Parse(zigArgs));

        if (args is ["bindings", .. var bindingsArgs])
            return BindingsCommand.Generate(Options.Parse(bindingsArgs));

        if (args is ["check", var name, .. var checkArgs] && checks.TryGetValue(name, out var check))
            return check(Options.Parse(checkArgs));

        Console.Error.WriteLine("usage: kabic generate [--root <dir>] [--manifest <file>] [--zig <path>] [--domain <name>]... [--into <dir>]");
        Console.Error.WriteLine("       kabic read | write csharp | write zig (see each command for its options)");
        Console.Error.WriteLine("       kabic bindings [--domain <name>]... [--print-config]");
        Console.Error.WriteLine($"       kabic check <{string.Join('|', checks.Keys)}> [--root <dir>] [--manifest <file>] [--zig <path>]");
        return 2;
    }
}
