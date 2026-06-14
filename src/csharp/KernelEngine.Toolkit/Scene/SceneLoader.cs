using System.Numerics;
using System.Reflection;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Parses a <c>.scene</c> TOML file and materializes its <c>[[entity]]</c>
/// entries into <see cref="Node"/>s on the target <see cref="NodeWorld"/>. Node
/// classes resolve through <see cref="NodeTypeRegistry"/>; their constructor
/// parameters are filled by the DI container; <c>[entity.properties]</c>
/// values are reflected onto public settable properties.
/// </summary>
public sealed class SceneLoader
{
    private readonly NodeTypeRegistry _types;

    public SceneLoader(NodeTypeRegistry types) { _types = types; }

    public void LoadInto(NodeWorld tree, IServiceProvider services, string path)
    {
        var entities = ReadEntities(path);
        if (entities is null) return;

        var instances = new List<(Node Node, TomlTable Entry, Dictionary<string, object?>? InheritedProps)>(entities.Count);
        var byName    = new Dictionary<string, Node>(StringComparer.Ordinal);

        foreach (var entity in entities)
        {
            var name = entity.TryGetValue("name", out var n) ? n as string : null;
            if (string.IsNullOrEmpty(name)) continue;

            string? typeName = null;
            Dictionary<string, object?>? inheritedProps = null;
            if (entity.TryGetValue("scene", out var subRaw) && subRaw is string subPath)
            {
                var resolved    = ResolveScenePath(path, subPath);
                var subEntities = ReadEntities(resolved);
                var template    = subEntities?.FirstOrDefault();
                if (template is null)
                    throw new InvalidOperationException($"Subscene '{resolved}' has no [[entity]] entries.");
                typeName       = template.TryGetValue("type", out var tt) ? tt as string : null;
                inheritedProps = template.TryGetValue("properties", out var tp) && tp is TomlTable tpt
                    ? tpt.ToDictionary(kv => kv.Key, kv => (object?)kv.Value) : null;
            }
            else if (entity.TryGetValue("type", out var t))
            {
                typeName = t as string;
            }

            if (string.IsNullOrEmpty(typeName))
                throw new InvalidOperationException(
                    $"Scene entity '{name}' is missing 'type' (and 'scene' didn't resolve).");

            var nodeType = _types.Resolve(typeName);
            var node     = (Node)ActivatorUtilities.CreateInstance(services, nodeType);

            instances.Add((node, entity, inheritedProps));
            byName[name] = node;
        }

        foreach (var (node, entry, inheritedProps) in instances)
        {
            var name = (string)entry["name"];
            Node? parent = null;
            if (entry.TryGetValue("parent", out var p) && p is string parentName
                && byName.TryGetValue(parentName, out var found))
            {
                parent = found;
            }

            tree.PreAddNode(node, name, parent);

            if (inheritedProps is not null)
                ApplyProperties(node, inheritedProps);
            if (entry.TryGetValue("properties", out var propsRaw) && propsRaw is TomlTable outerProps)
                ApplyProperties(node, outerProps.ToDictionary(kv => kv.Key, kv => (object?)kv.Value));

            tree.CompleteAddNode(node);
        }
    }

    private static List<TomlTable>? ReadEntities(string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"Scene file not found: {path}", path);
        var text = File.ReadAllText(path);
        var doc  = Toml.ToModel(text);

        if (!doc.TryGetValue("entity", out var entitiesRaw)) return null;
        return entitiesRaw switch
        {
            TomlTableArray tta => tta.Cast<TomlTable>().ToList(),
            TomlArray      ta  => ta.OfType<TomlTable>().ToList(),
            _ => null,
        };
    }

    private static string ResolveScenePath(string outerPath, string subRef)
    {
        var s = subRef.StartsWith("res://", StringComparison.Ordinal) ? subRef.Substring(6) : subRef;
        if (Path.IsPathRooted(s)) return s;
        if (subRef.StartsWith("res://", StringComparison.Ordinal))
            return Path.Combine(AppContext.BaseDirectory, s);
        return Path.Combine(Path.GetDirectoryName(outerPath) ?? AppContext.BaseDirectory, s);
    }

    private static readonly HashSet<string> s_transformProps = new(StringComparer.Ordinal)
    {
        "Position", "Scale", "Rotation",
    };

    private static void ApplyProperties(Node node, IReadOnlyDictionary<string, object?> props)
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
                    $"Could not bind scene property '{key}' on {nodeType.Name}: {ex.Message}", ex);
            }
        }
    }

    private static PropertyInfo? FindProperty(Type type, string name)
    {
        foreach (var p in type.GetProperties(BindingFlags.Public | BindingFlags.Instance))
            if (string.Equals(p.Name, name, StringComparison.OrdinalIgnoreCase)) return p;
        return null;
    }

    private static void ApplyTransformProperty(Node node, string key, object? raw)
    {
        var transform = node.LocalTransform;
        switch (key)
        {
            case "Position": transform = transform with { Position = ToVector3(raw) }; break;
            case "Scale":    transform = transform with { Scale    = ToVector3(raw) }; break;
            case "Rotation":
                if (raw is TomlArray rot && rot.Count == 4)
                    transform = transform with
                    {
                        Rotation = new Quaternion(ToFloat(rot[0]), ToFloat(rot[1]), ToFloat(rot[2]), ToFloat(rot[3])),
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
            2    => new Vector3(ToFloat(a[0]), ToFloat(a[1]), 0f),
            >= 3 => new Vector3(ToFloat(a[0]), ToFloat(a[1]), ToFloat(a[2])),
            _    => throw new InvalidOperationException($"Vector3 needs ≥2 elements, got {a.Count}."),
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
