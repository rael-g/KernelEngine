using Kabic.ClangSharpBackend;

namespace Kabic.Cli;

internal static class BindingsCommand
{
    public static int Generate(Options options)
    {
        var jobs = Select(options);
        if (options.Raw.Contains("--print-config"))
        {
            foreach (var job in jobs) Console.WriteLine($"# {job.Name}\n{job.Print()}");
            return 0;
        }

        var resourceDir = ClangResourceDir.EnsureAsync(options.Root).GetAwaiter().GetResult();
        var succeeded = 0;
        foreach (var job in jobs)
        {
            Console.WriteLine($"--- Generating: {job.Name}");
            var target = Path.GetFullPath(Path.Combine(job.NativeDir, job.Output));
            var previous = target.TrimEnd(Path.DirectorySeparatorChar) + ".previous";
            var hadPrevious = Directory.Exists(target);
            if (hadPrevious)
            {
                if (Directory.Exists(previous)) Directory.Delete(previous, recursive: true);
                Directory.Move(target, previous);
            }

            BindingRun run;
            try
            {
                run = ClangSharpRunner.Run(job, options.Root, resourceDir, target);
            }
            catch
            {
                Restore(target, previous, hadPrevious);
                throw;
            }

            var wrote = Directory.Exists(target) && Directory.EnumerateFiles(target, "*.cs", SearchOption.AllDirectories).Any();
            if (wrote)
            {
                if (hadPrevious) Directory.Delete(previous, recursive: true);
                succeeded++;
                if (!run.Succeeded) foreach (var line in run.Log) Console.WriteLine($"    {line}");
            }
            else
            {
                Restore(target, previous, hadPrevious);
                Console.WriteLine($"FAILED: {job.Name} wrote no bindings; the previous bindings were kept");
                foreach (var line in run.Log) Console.WriteLine($"    {line}");
            }
        }

        Console.WriteLine($"\nDone. {succeeded}/{jobs.Count} bindings regenerated successfully.");
        return succeeded == jobs.Count ? 0 : 1;
    }

    public static int CheckDrift(Options options)
    {
        var jobs = Select(options);
        var resourceDir = ClangResourceDir.EnsureAsync(options.Root).GetAwaiter().GetResult();
        var scratch = Path.Combine(Path.GetTempPath(), "kabic_bindings_check_" + Guid.NewGuid().ToString("N")[..8]);
        var drift = new List<string>();
        var failed = 0;
        try
        {
            foreach (var job in jobs)
            {
                var target = Path.Combine(scratch, job.Name);
                Directory.CreateDirectory(target);
                ClangSharpRunner.Run(job, options.Root, resourceDir, target);
                var committed = Path.GetFullPath(Path.Combine(job.NativeDir, job.Output));
                if (!Directory.EnumerateFiles(target, "*.cs", SearchOption.AllDirectories).Any())
                {
                    Console.WriteLine($"[?] {job.Name}: the generator wrote nothing, so nothing was compared");
                    failed++;
                }
                else if (!Directory.Exists(committed))
                {
                    Console.WriteLine($"[DRIFT] {job.Name}: the committed output directory is missing");
                    drift.Add(job.Name);
                }
                else if (!SameTree(target, committed))
                {
                    Console.WriteLine($"[DRIFT] {job.Name}: the committed bindings differ from what the headers generate");
                    drift.Add(job.Name);
                }
            }
        }
        finally
        {
            if (Directory.Exists(scratch)) Directory.Delete(scratch, recursive: true);
        }

        if (drift.Count > 0)
        {
            Console.WriteLine("\n[FAIL] Drift detected! Run 'kabic bindings' and commit the changes.");
            return 1;
        }
        if (failed > 0)
        {
            Console.WriteLine("\nThe check could not run to completion; it says nothing about drift.");
            return 2;
        }
        Console.WriteLine($"[OK] All {jobs.Count} bindings are up to date.");
        return 0;
    }

    static IReadOnlyList<BindingJob> Select(Options options) =>
        BindingsPlanner.Plan(options.Root, options.Manifest)
            .Where(j => options.Domains.Count == 0 || options.Domains.Contains(j.Name))
            .ToList();

    static void Restore(string target, string previous, bool hadPrevious)
    {
        if (!hadPrevious) return;
        if (Directory.Exists(target)) Directory.Delete(target, recursive: true);
        Directory.Move(previous, target);
    }

    static bool SameTree(string a, string b)
    {
        var left = Directory.EnumerateFiles(a, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(a, f)).Order().ToList();
        var right = Directory.EnumerateFiles(b, "*", SearchOption.AllDirectories).Select(f => Path.GetRelativePath(b, f)).Order().ToList();
        return left.SequenceEqual(right)
            && left.All(rel => File.ReadAllBytes(Path.Combine(a, rel)).AsSpan().SequenceEqual(File.ReadAllBytes(Path.Combine(b, rel))));
    }
}
