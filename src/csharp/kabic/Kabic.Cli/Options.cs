namespace Kabic.Cli;

internal sealed record Options(string Root, string Manifest, string? Zig, IReadOnlyList<string> Domains, string? Into)
{
    public static Options Parse(IReadOnlyList<string> args)
    {
        var root = Directory.GetCurrentDirectory();
        string? manifest = null;
        string? zig = null;
        string? into = null;
        var domains = new List<string>();
        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case "--root": root = Path.GetFullPath(args[++i]); break;
                case "--manifest": manifest = Path.GetFullPath(args[++i]); break;
                case "--zig": zig = args[++i]; break;
                case "--domain": domains.Add(args[++i]); break;
                case "--into": into = Path.GetFullPath(args[++i]); break;
            }
        }
        return new Options(root, manifest ?? Path.Combine(root, "scripts", "api_domains.json"), zig, domains, into);
    }
}
