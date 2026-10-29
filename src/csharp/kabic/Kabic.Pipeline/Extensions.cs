using System.Text.Json.Nodes;

namespace Kabic.Pipeline;

/// <summary>
/// Logic a host adds to a kabic run: it reads every domain the run read and emits files of its
/// own. An extension only adds files; it never edits a file another wrote.
/// </summary>
public interface IKabicExtension
{
    /// <summary>The name its section of the manifest's <c>extensions</c> object is keyed by.</summary>
    string Name { get; }

    /// <summary>Reads what <paramref name="context"/> holds and emits through it.</summary>
    void Run(ExtensionContext context);
}

/// <summary>One domain of the manifest and the API model its headers were read into.</summary>
public sealed record DomainModel(DomainSpec Spec, ApiModel Model);

/// <summary>
/// What an extension is given: every domain read, the convention, its own manifest section, the
/// tree the writers wrote into, and the sink its files go through.
/// </summary>
public sealed class ExtensionContext
{
    private readonly Func<string, string> _place;
    private readonly Dictionary<string, string> _emitted;
    private readonly List<string> _reports;
    private readonly string? _zig;

    internal ExtensionContext(IReadOnlyList<DomainModel> domains, Convention convention, JsonObject? options,
        string root, string manifestPath, string? zig, Func<string, string> place, Dictionary<string, string> emitted, List<string> reports)
    {
        _zig = zig;
        ManifestPath = manifestPath;
        Domains = domains;
        Convention = convention;
        Options = options;
        Root = root;
        _place = place;
        _emitted = emitted;
        _reports = reports;
    }

    /// <summary>Every domain of the manifest, in manifest order.</summary>
    public IReadOnlyList<DomainModel> Domains { get; }

    /// <summary>The manifest's convention.</summary>
    public Convention Convention { get; }

    /// <summary>The extension's section of the manifest's <c>extensions</c> object, or null.</summary>
    public JsonObject? Options { get; }

    /// <summary>The root the manifest's paths are relative to.</summary>
    public string Root { get; }

    /// <summary>The path of the manifest the run reads.</summary>
    public string ManifestPath { get; }

    /// <summary>
    /// The text at <paramref name="path"/>, relative to the root: what an earlier extension of this
    /// run emitted there, else what the tree holds, else null.
    /// </summary>
    public string? Read(string path)
    {
        if (_emitted.TryGetValue(path, out var text)) return text;
        var file = _place(path);
        return File.Exists(file) ? File.ReadAllText(file) : null;
    }

    /// <summary>
    /// Emits <paramref name="text"/> at <paramref name="path"/>, relative to the root. A path
    /// already emitted in this run is reported as a failure and keeps its first text.
    /// </summary>
    public void Emit(string path, string text)
    {
        if (!_emitted.TryAdd(path, text)) Report($"{path} is emitted twice");
    }

    /// <summary>
    /// Reads <paramref name="headers"/>, paths relative to the root, into an API model, as a
    /// domain's headers are read; <paramref name="auxHeaders"/> are read for the types they
    /// declare and are marked external. Throws <c>InvalidOperationException</c> when they do not
    /// parse.
    /// </summary>
    public ApiModel ReadHeaders(IEnumerable<string> headers, IEnumerable<string> includeDirs, IEnumerable<string> auxHeaders)
    {
        List<string> Rooted(IEnumerable<string> paths) => [.. paths.Select(p => Path.Combine(Root, p))];
        var json = Extraction.Run(new Extraction.Request(Rooted(headers), Rooted(includeDirs), Rooted(auxHeaders), [], _zig, Convention));
        return ApiReader.Read(JsonNode.Parse(json)!.AsObject());
    }

    /// <summary>Records a failure; the run fails once every extension has run.</summary>
    public void Report(string message) => _reports.Add(message);
}

/// <summary>Runs the extensions a host composed, in order, after the writers.</summary>
public static class ExtensionRunner
{
    /// <summary>
    /// Runs <paramref name="extensions"/> over <paramref name="domains"/> and returns every file
    /// they emitted, keyed by its path relative to <paramref name="root"/>. Throws
    /// <c>InvalidOperationException</c> with every report when any extension reported a failure.
    /// </summary>
    public static IReadOnlyDictionary<string, string> Run(IReadOnlyList<IKabicExtension> extensions,
        IReadOnlyList<DomainModel> domains, Convention convention, string manifestPath, string root, string? zig,
        Func<string, string> place)
    {
        var manifest = JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject();
        var emitted = new Dictionary<string, string>(StringComparer.Ordinal);
        var reports = new List<string>();
        var sections = manifest["extensions"]?.AsObject();
        foreach (var extension in extensions)
        {
            var context = new ExtensionContext(domains, convention, sections?[extension.Name]?.AsObject(),
                root, manifestPath, zig, place, emitted, reports);
            extension.Run(context);
        }
        if (reports.Count > 0)
            throw new InvalidOperationException(string.Join('\n', reports));
        return emitted;
    }

    /// <summary>The domains of <paramref name="specs"/> read from their API descriptions.</summary>
    public static IReadOnlyList<DomainModel> Models(IReadOnlyList<DomainSpec> specs, IReadOnlyDictionary<string, string> apis) =>
        [.. specs.Select(s => new DomainModel(s, ApiReader.Read(JsonNode.Parse(apis[s.Name])!.AsObject())))];
}
