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

    internal ExtensionContext(IReadOnlyList<DomainModel> domains, Convention convention, JsonObject? options,
        string root, Func<string, string> place, Dictionary<string, string> emitted, List<string> reports)
    {
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
        IReadOnlyList<DomainModel> domains, Convention convention, JsonObject manifest, string root,
        Func<string, string> place)
    {
        var emitted = new Dictionary<string, string>(StringComparer.Ordinal);
        var reports = new List<string>();
        var sections = manifest["extensions"]?.AsObject();
        foreach (var extension in extensions)
        {
            var context = new ExtensionContext(domains, convention, sections?[extension.Name]?.AsObject(),
                root, place, emitted, reports);
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
