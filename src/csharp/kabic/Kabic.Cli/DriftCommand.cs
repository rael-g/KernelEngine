using Kabic.Pipeline;

namespace Kabic.Cli;

internal static class DriftCommand
{
    public static int Run(Options options)
    {
        var rootDir = options.Root;
        var zigOverride = options.Zig;
        var specs = DomainSpec.Load(options.Manifest);

        Console.WriteLine("Checking for ke_api.json drift (headers vs. generated C#)...");

        var driftDetected = false;
        var checkFailed = false;
        var tmpRoot = Path.Combine(Path.GetTempPath(), "ke_api_drift_" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tmpRoot);

        try
        {
            var extracted = new Dictionary<string, string>();
            var extractionFailures = new Dictionary<string, string>();
            Parallel.ForEach(specs, spec =>
            {
                try
                {
                    var json = Regeneration.ExtractOne(spec, rootDir, zigOverride);
                    lock (extracted) extracted[spec.Name] = json;
                }
                catch (InvalidOperationException e)
                {
                    lock (extractionFailures) extractionFailures[spec.Name] = e.Message;
                }
            });

            foreach (var spec in specs)
            {
                var name = spec.Name;
                if (extractionFailures.TryGetValue(name, out var extractErr))
                {
                    Console.WriteLine($"[?] {name}: could not extract the headers, so nothing was compared:\n{extractErr}");
                    checkFailed = true;
                    continue;
                }

                var apiJson = extracted[name];
                var committed = Regeneration.Plan(spec, p => Path.Combine(rootDir, p));
                var tmpApiJson = Path.Combine(tmpRoot, $"{name}.ke_api.json");
                File.WriteAllText(tmpApiJson, apiJson);

                if (!FilesEqual(tmpApiJson, committed.ApiJson))
                {
                    Console.WriteLine($"[!] {name}: ke_api.json is out of date "
                        + $"(committed: {Path.GetRelativePath(rootDir, committed.ApiJson)})");
                    driftDetected = true;
                }

                var tmpOutDir = Path.Combine(tmpRoot, name, "out");
                var tmpContractDir = spec.AbstractionsOutDir is not null ? Path.Combine(tmpRoot, name, "abstractions") : tmpOutDir;
                var tmpCFile = spec.CFieldTable is null ? null : Path.Combine(tmpRoot, name, "component_fields.h");

                try
                {
                    Regeneration.GenerateOne(spec, apiJson, new DomainOutput(tmpApiJson, tmpOutDir, tmpContractDir, tmpCFile));
                }
                catch (InvalidOperationException e)
                {
                    Console.WriteLine($"[?] {name}: could not generate, so nothing was compared:\n{e.Message}");
                    checkFailed = true;
                    continue;
                }

                if (!DirsEqual(tmpOutDir, committed.OutDir) || !DirsEqual(tmpContractDir, committed.ContractDir))
                {
                    Console.WriteLine($"[!] {name}: generated C# is out of date "
                        + $"(committed: {Path.GetRelativePath(rootDir, committed.OutDir)})");
                    driftDetected = true;
                }

                if (tmpCFile is not null && committed.CFieldTableFile is { } committedCFile && !FilesEqual(tmpCFile, committedCFile))
                {
                    Console.WriteLine($"[!] {name}: generated C field table is out of date "
                        + $"(committed: {Path.GetRelativePath(rootDir, committedCFile)})");
                    driftDetected = true;
                }
            }
        }
        finally
        {
            Directory.Delete(tmpRoot, recursive: true);
        }

        if (driftDetected)
        {
            Console.WriteLine("\nDrift detected. Regenerate with:");
            Console.WriteLine("  dotnet run --project src/csharp/kabic/Kabic.Cli -- generate");
            return 1;
        }

        if (checkFailed)
        {
            Console.WriteLine("\nThe check could not run to completion; it says nothing about drift.");
            return 2;
        }

        Console.WriteLine("No drift detected.");
        return 0;
    }

    static bool FilesEqual(string a, string b) =>
        File.Exists(b) && File.ReadAllBytes(a).AsSpan().SequenceEqual(File.ReadAllBytes(b));

    static bool DirsEqual(string a, string b)
    {
        if (!Directory.Exists(a)) return true;
        if (!Directory.Exists(b)) return !Directory.EnumerateFileSystemEntries(a).Any();
        var aFiles = Directory.EnumerateFiles(a, "*", SearchOption.AllDirectories)
            .Select(f => Path.GetRelativePath(a, f));
        return aFiles.All(rel => FilesEqual(Path.Combine(a, rel), Path.Combine(b, rel)));
    }
}
