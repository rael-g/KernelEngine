using System.Text.Json.Nodes;
using Kabic.Numerics;

namespace Kabic;

/// <summary>
/// The packs kabic ships, by the name a manifest uses for them, and the loader that reads a manifest's
/// convention with those packs available. A pack of another project is added with
/// <see cref="ConventionBuilder.Use"/> instead.
/// </summary>
/// <remarks>
/// <c>Pack</c> maps a pack name to a new instance of the pack it names, and throws an
/// <c>InvalidOperationException</c> for any other name. <c>Load</c> parses the file at the given
/// path as JSON and takes the object under the key <c>convention</c>, throwing an
/// <c>InvalidOperationException</c> when that key is absent. It passes that object to
/// <c>Convention.FromJson</c> together with <c>Pack</c>, the function that resolves pack names.
/// </remarks>
public static class ConventionLoader
{
    /// <summary>The shipped pack called <paramref name="name"/>.</summary>
    public static IShapePack Pack(string name) => name switch
    {
        "numerics" => new NumericsPack(),
        _ => throw new InvalidOperationException($"kabic ships no pack called '{name}'"),
    };

    /// <summary>Reads the <c>convention</c> object of the manifest at <paramref name="manifestPath"/>.</summary>
    public static Convention Load(string manifestPath) =>
        Convention.FromJson(JsonNode.Parse(File.ReadAllText(manifestPath))!.AsObject()["convention"]?.AsObject()
            ?? throw new InvalidOperationException($"{manifestPath} has no 'convention' object"), Pack);
}
