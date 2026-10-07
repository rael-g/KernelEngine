namespace Kabic.Pipeline;

public sealed record DomainOutput(
    string ApiJson,
    string OutDir,
    string ContractDir);

public static class Regeneration
{
    public static DomainOutput Plan(DomainSpec spec, Func<string, string> place)
    {
        var outDir = place(spec.OutDir);
        return new DomainOutput(
            place(spec.ApiJson),
            outDir,
            spec.AbstractionsOutDir is null ? outDir : place(spec.AbstractionsOutDir));
    }

    public static Extraction.Request RequestFor(DomainSpec spec, string rootDir, string? zig, Convention convention)
    {
        List<string> Rooted(IEnumerable<string> paths) => paths.Select(p => Path.Combine(rootDir, p)).ToList();
        return new Extraction.Request(Rooted(spec.Headers), Rooted(spec.IncludeDirs),
            Rooted(spec.AuxHeaders), Rooted(spec.ComposeHeaders), zig, convention);
    }

    public static string ExtractOne(DomainSpec spec, string rootDir, string? zig, Convention convention) =>
        Extraction.Run(RequestFor(spec, rootDir, zig, convention));

    public static void GenerateOne(DomainSpec spec, string apiJson, DomainOutput output, Convention convention)
    {
        Generation.CSharp(new Generation.CSharpRequest(
            apiJson, spec.Namespace, spec.NativeNamespace, output.OutDir, output.ContractDir,
            spec.Name, spec.Library, spec.Providers, [], spec.Usings, convention));
    }

    public static IReadOnlyDictionary<string, string> ExtractAll(
        IReadOnlyList<DomainSpec> specs, string rootDir, string? zig, Convention convention)
    {
        var results = new System.Collections.Concurrent.ConcurrentDictionary<string, string>();
        var failures = new System.Collections.Concurrent.ConcurrentDictionary<string, string>();
        Parallel.ForEach(specs, spec =>
        {
            try { results[spec.Name] = ExtractOne(spec, rootDir, zig, convention); }
            catch (Exception e) { failures[spec.Name] = e.Message; }
        });
        if (!failures.IsEmpty)
            throw new InvalidOperationException(string.Join('\n',
                specs.Where(s => failures.ContainsKey(s.Name)).Select(s => $"{s.Name}: {failures[s.Name]}")));
        return results;
    }
}
