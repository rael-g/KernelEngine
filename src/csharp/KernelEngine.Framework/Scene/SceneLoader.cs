using System.Numerics;
using System.Reflection;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Parses a <c>.scene</c> TOML file and materializes its <c>[[entity]]</c>
/// entries into <see cref="Node"/>s on the target <see cref="Tree"/>. Node
/// classes resolve through <see cref="NodeTypeRegistry"/>; their constructor
/// parameters are filled by the DI container; <c>[entity.properties]</c>
/// values are reflected onto public settable properties (and a small set of
/// well-known fields routed through <see cref="Node.LocalTransform"/>).
/// </summary>
/// <remarks>
/// Scene grammar (subset supported today):
/// <code>
/// [scene]
/// name    = "Main"
/// version = 1
///
/// [[entity]]
/// name   = "Sun"
/// type   = "DirectionalLight"           # resolves via NodeTypeRegistry
/// parent = "ParentName"                 # optional, references an earlier [[entity]]
/// [entity.properties]
/// Direction = [0.5, 1.0, 0.5]           # → Vector3 (auto from float array)
/// Color     = [1.0, 1.0, 1.0]
/// Intensity = 3.0
/// </code>
/// Properties named <c>Position</c>, <c>Scale</c>, <c>Rotation</c> are routed
/// onto the node's <see cref="Node.LocalTransform"/>; everything else reflects
/// onto the matching public property on the concrete node type.
/// </remarks>
public sealed class SceneLoader
{
    private readonly NodeTypeRegistry _types;

    public SceneLoader(NodeTypeRegistry types) { _types = types; }

    public void LoadInto(Tree tree, IServiceProvider services, string path)
    {
        var text = File.ReadAllText(path);
        var doc  = Toml.ToModel(text);

        if (!doc.TryGetValue("entity", out var entitiesRaw) || entitiesRaw is not TomlArray entities)
            return;

        // Two-pass: instantiate every entity first (so parent references resolve
        // even when declared above their parent in the file), then attach to
        // parents + populate properties.
        var instances = new List<(Node Node, TomlTable Entry)>(entities.Count);
        var byName    = new Dictionary<string, Node>(StringComparer.Ordinal);

        foreach (var entry in entities)
        {
            if (entry is not TomlTable entity) continue;
            var name = entity.TryGetValue("name", out var n) ? n as string : null;
            if (string.IsNullOrEmpty(name)) continue;

            var typeName = entity.TryGetValue("type", out var t) ? t as string : null;
            if (string.IsNullOrEmpty(typeName))
                throw new InvalidOperationException(
                    $"Scene entity '{name}' is missing 'type'.");

            var nodeType = _types.Resolve(typeName);
            var node     = (Node)ActivatorUtilities.CreateInstance(services, nodeType);

            instances.Add((node, entity));
            byName[name] = node;
        }

        foreach (var (node, entry) in instances)
        {
            var name   = (string)entry["name"];
            Node? parent = null;
            if (entry.TryGetValue("parent", out var p) && p is string parentName
                && byName.TryGetValue(parentName, out var found))
            {
                parent = found;
            }
            tree.AddNode(node, name, parent);

            if (entry.TryGetValue("properties", out var propsRaw) && propsRaw is TomlTable props)
                ApplyProperties(node, props);
        }
    }

    // ── Property reflection ─────────────────────────────────────────────────

    private static readonly HashSet<string> s_transformProps = new(StringComparer.Ordinal)
    {
        "Position", "Scale", "Rotation",
    };

    private static void ApplyProperties(Node node, TomlTable props)
    {
        var nodeType = node.GetType();

        foreach (var (key, raw) in props)
        {
            if (s_transformProps.Contains(key))
            {
                ApplyTransformProperty(node, key, raw);
                continue;
            }

            var prop = FindProperty(nodeType, key);
            if (prop is null || !prop.CanWrite) continue;

            try
            {
                var converted = Convert(raw, prop.PropertyType);
                prop.SetValue(node, converted);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException(
                    $"Could not bind scene property '{key}' on {nodeType.Name}: {ex.Message}",
                    ex);
            }
        }
    }

    private static PropertyInfo? FindProperty(Type type, string name)
    {
        // Case-insensitive walk over the node's public instance properties.
        foreach (var p in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return p;
        return null;
    }

    private static void ApplyTransformProperty(Node node, string key, object? raw)
    {
        var transform = node.LocalTransform;
        switch (key)
        {
            case "Position":
                transform = transform with { Position = ToVector3(raw) };
                break;
            case "Scale":
                transform = transform with { Scale = ToVector3(raw) };
                break;
            case "Rotation":
                if (raw is TomlArray rot && rot.Count == 4)
                    transform = transform with
                    {
                        Rotation = new Quaternion(
                            ToFloat(rot[0]), ToFloat(rot[1]),
                            ToFloat(rot[2]), ToFloat(rot[3])),
                    };
                break;
        }
        node.LocalTransform = transform;
    }

    private static object? Convert(object? raw, Type targetType)
    {
        if (raw is null) return null;
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;
        if (underlying.IsInstanceOfType(raw)) return raw;

        if (raw is TomlArray array)
        {
            if (underlying == typeof(Vector2)) return ToVector2(array);
            if (underlying == typeof(Vector3)) return ToVector3(array);
            if (underlying == typeof(Vector4)) return ToVector4(array);
        }

        if (underlying.IsEnum)
        {
            return raw switch
            {
                string s => Enum.Parse(underlying, s, ignoreCase: true),
                long l   => Enum.ToObject(underlying, l),
                _        => Enum.ToObject(underlying, System.Convert.ToInt64(raw)),
            };
        }

        return System.Convert.ChangeType(raw, underlying, System.Globalization.CultureInfo.InvariantCulture);
    }

    private static Vector2 ToVector2(object? raw)
    {
        if (raw is not TomlArray a || a.Count < 2)
            throw new InvalidOperationException($"Expected a 2-element array, got '{raw}'.");
        return new Vector2(ToFloat(a[0]), ToFloat(a[1]));
    }

    private static Vector3 ToVector3(object? raw)
    {
        if (raw is not TomlArray a)
            throw new InvalidOperationException($"Expected a numeric array, got '{raw}'.");
        return a.Count switch
        {
            2 => new Vector3(ToFloat(a[0]), ToFloat(a[1]), 0f),
            >= 3 => new Vector3(ToFloat(a[0]), ToFloat(a[1]), ToFloat(a[2])),
            _ => throw new InvalidOperationException($"Vector3 needs ≥2 elements, got {a.Count}."),
        };
    }

    private static Vector4 ToVector4(object? raw)
    {
        if (raw is not TomlArray a || a.Count < 4)
            throw new InvalidOperationException($"Expected a 4-element array, got '{raw}'.");
        return new Vector4(ToFloat(a[0]), ToFloat(a[1]), ToFloat(a[2]), ToFloat(a[3]));
    }

    private static float ToFloat(object? v) =>
        v is null ? 0f : System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture);
}
