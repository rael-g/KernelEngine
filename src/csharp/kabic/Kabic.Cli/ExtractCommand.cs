using Kabic.Pipeline;

namespace Kabic.Cli;

internal static class ExtractCommand
{
    public static int Run(IReadOnlyList<string> args)
    {
        string? outPath = null;
        string? zigOverride = null;
        string? manifest = null;
        var includeDirs = new List<string>();
        var headers = new List<string>();
        var auxHeaders = new List<string>();
        var composeHeaders = new List<string>();

        for (var i = 0; i < args.Count; i++)
        {
            switch (args[i])
            {
                case "--out": outPath = args[++i]; break;
                case "--zig": zigOverride = args[++i]; break;
                case "--manifest": manifest = args[++i]; break;
                case "-I": includeDirs.Add(args[++i]); break;
                case "--aux": auxHeaders.Add(args[++i]); break;
                case "--compose": composeHeaders.Add(args[++i]); break;
                default: headers.Add(args[i]); break;
            }
        }

        if (outPath is null || headers.Count == 0)
        {
            Console.Error.WriteLine("usage: kabic extract --out <path> [-I <dir>]... "
                + "[--aux <header.h>]... [--compose <header.h>]... <header.h>...");
            return 1;
        }

        string json;
        try
        {
            json = Extraction.Run(new Extraction.Request(headers, includeDirs, auxHeaders, composeHeaders, zigOverride,
                ConventionLoader.Load(manifest ?? Path.Combine("scripts", "api_domains.json"))));
        }
        catch (InvalidOperationException e)
        {
            Console.Error.WriteLine(e.Message);
            return 1;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outPath))!);
        File.WriteAllText(outPath, json);
        Console.WriteLine($"wrote {outPath}");
        return 0;
    }
}
