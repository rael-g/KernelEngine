using Kabic.Pipeline;
using Kabic.Conventions;

namespace Kabic.Cli;

/// <summary>
/// Implements the read command, which reads an API description from C headers.
/// </summary>
/// <remarks>
/// Run separates the arguments into the output path, the zig override, the manifest, include
/// directories, auxiliary headers, compose headers and primary headers. Any other argument,
/// including an unrecognised flag, is a primary header. Without an output path or a primary
/// header the usage is written to the error stream and the command returns one. Otherwise
/// <c>Extraction.Run</c> produces the JSON, and its <c>InvalidOperationException</c> is written
/// to the error stream. On success the output directory is created, the JSON is written there,
/// and the path is printed.
/// </remarks>
internal static class ReadCommand
{
    /// <summary>
    /// Extracts the API of the given headers into the output path and returns zero. Returns one
    /// when an argument is missing or the extraction fails.
    /// </summary>
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
            Console.Error.WriteLine("usage: kabic read --out <path> [-I <dir>]... "
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
