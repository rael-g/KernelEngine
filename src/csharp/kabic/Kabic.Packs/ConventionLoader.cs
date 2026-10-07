using System.Text.Json.Nodes;
using Kabic.Numerics;

namespace Kabic;

/// <summary>
/// The packs kabic ships, by the name a manifest uses for them, and the loader that reads a manifest's
/// convention with those packs available. A pack of another project is added with
/// <see cref="ConventionBuilder.Use"/> instead.
/// </summary>
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
