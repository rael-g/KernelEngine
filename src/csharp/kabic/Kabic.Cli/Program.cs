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

if (args is ["extract", .. var extractArgs])
    return ExtractCommand.Run(extractArgs);

if (args is ["csharp", .. var csharpArgs])
    return CSharpCommand.Run(csharpArgs);

if (args is ["zig", .. var zigArgs])
    return ZigCommand.Run(zigArgs);

if (args is ["bindings", .. var bindingsArgs])
    return BindingsCommand.Generate(Options.Parse(bindingsArgs));

if (args is ["check", var name, .. var checkArgs] && checks.TryGetValue(name, out var check))
    return check(Options.Parse(checkArgs));

Console.Error.WriteLine("usage: kabic generate [--root <dir>] [--manifest <file>] [--zig <path>] [--domain <name>]... [--into <dir>]");
Console.Error.WriteLine("       kabic extract | csharp | zig (see each command for its options)");
Console.Error.WriteLine("       kabic bindings [--domain <name>]... [--print-config]");
Console.Error.WriteLine($"       kabic check <{string.Join('|', checks.Keys)}> [--root <dir>] [--manifest <file>] [--zig <path>]");
return 2;
