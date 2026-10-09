using Kabic.Cli;
using Kabic.Cli.Checks;

var checks = new Dictionary<string, Func<Options, int>>
{
    ["drift"] = DriftCommand.Run,
    ["bindings"] = BindingsCommand.CheckDrift,
    ["api-coverage"] = ApiCoverageCheck.Execute,
    ["reconstruction"] = ReconstructionCheck.Execute,
    ["out-params"] = OutParamsCheck.Execute,
};

if (args is ["generate", .. var generateArgs])
    return GenerateCommand.Run(Options.Parse(generateArgs));

if (args is ["read", .. var readArgs])
    return ReadCommand.Run(readArgs);

if (args is ["write", "csharp", .. var csharpArgs])
    return WriteCSharpCommand.Run(csharpArgs);

if (args is ["write", "zig", .. var zigArgs])
    return WriteZigCommand.Run(zigArgs);

if (args is ["bindings", .. var bindingsArgs])
    return BindingsCommand.Generate(Options.Parse(bindingsArgs));

if (args is ["check", var name, .. var checkArgs] && checks.TryGetValue(name, out var check))
    return check(Options.Parse(checkArgs));

Console.Error.WriteLine("usage: kabic generate [--root <dir>] [--manifest <file>] [--zig <path>] [--domain <name>]... [--into <dir>]");
Console.Error.WriteLine("       kabic read | write csharp | write zig (see each command for its options)");
Console.Error.WriteLine("       kabic bindings [--domain <name>]... [--print-config]");
Console.Error.WriteLine($"       kabic check <{string.Join('|', checks.Keys)}> [--root <dir>] [--manifest <file>] [--zig <path>]");
return 2;
