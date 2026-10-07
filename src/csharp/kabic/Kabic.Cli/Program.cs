using Kabic.Cli;
using Kabic.Cli.Checks;

var checks = new Dictionary<string, Func<Options, int>>
{
    ["drift"] = DriftCommand.Run,
    ["abi-layout"] = AbiLayoutCheck.Execute,
    ["api-coverage"] = ApiCoverageCheck.Execute,
    ["component-fields"] = ComponentFieldsCheck.Execute,
    ["generator-contract"] = GeneratorContractCheck.Execute,
    ["reconstruction"] = ReconstructionCheck.Execute,
};

if (args is ["generate", .. var generateArgs])
    return GenerateCommand.Run(Options.Parse(generateArgs));

if (args is ["check", var name, .. var checkArgs] && checks.TryGetValue(name, out var check))
    return check(Options.Parse(checkArgs));

Console.Error.WriteLine("usage: kabic generate [--root <dir>] [--manifest <file>] [--zig <path>] [--domain <name>]... [--into <dir>]");
Console.Error.WriteLine($"       kabic check <{string.Join('|', checks.Keys)}> [--root <dir>] [--manifest <file>] [--zig <path>]");
return 2;
