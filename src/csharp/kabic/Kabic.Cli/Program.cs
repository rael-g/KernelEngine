using Kabic.Cli;

return args switch
{
    ["generate", .. var rest] => GenerateCommand.Run(Options.Parse(rest)),
    ["check", "drift", .. var rest] => DriftCommand.Run(Options.Parse(rest)),
    _ => Usage(),
};

static int Usage()
{
    Console.Error.WriteLine("usage: kabic generate [--root <dir>] [--manifest <file>] [--zig <path>] [--domain <name>]... [--into <dir>]");
    Console.Error.WriteLine("       kabic check drift [--root <dir>] [--manifest <file>] [--zig <path>]");
    return 2;
}
