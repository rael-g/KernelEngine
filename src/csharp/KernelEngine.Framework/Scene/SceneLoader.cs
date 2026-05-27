using System.Numerics;
using System.Reflection;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.Framework;

/// <summary>
/// Loads a <c>*.scene.toml</c> file (see Reference ch.15 §5 + ch.17) into a live <see cref="Tree"/>.
///
/// <para>
/// MVP scope: built-in node types resolved by short name in the <c>KernelEngine.Framework</c>
/// namespace; user types resolved by fully qualified name across loaded assemblies. Public
/// settable properties are hydrated via reflection (primitives, enums, <see cref="Vector3"/>,
/// <see cref="Vector4"/>, <see cref="Quaternion"/> from TOML arrays). Transform position/rotation/scale
/// supported. Parents resolved by <see cref="Node.Name"/> — a parent must appear earlier in the array
/// than its children. Resource references (Mesh/Material/Texture) and sub-scene <c>include</c> are
/// deferred to later slices; for now game code attaches resources to nodes by name after loading.
/// </para>
/// </summary>
public static class SceneLoader
{
    /// <summary>
    /// Reads the scene TOML at <paramref name="path"/> and adds its nodes under <paramref name="tree"/>.
    /// Each node's name from the file is used as the Tree node name; <see cref="Tree.FindNode"/> can
    /// then locate them for post-load wiring (resources, signals, etc.).
    /// </summary>
    public static void Load(Tree tree, string path)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"Scene file not found: {path}");

        var doc = Toml.ToModel(File.ReadAllText(path));
        if (!doc.TryGetValue("node", out var rawNodes) || rawNodes is not TomlTableArray nodes)
            return; // empty scene

        // name → constructed Node (parent lookup table)
        var byName = new Dictionary<string, Node>(StringComparer.Ordinal);

        foreach (var entry in nodes)
        {
            var name = GetString(entry, "name") ?? throw new InvalidDataException("[[node]] entry missing 'name'");
            var typeName = GetString(entry, "type") ?? "Node";

            var parent = GetString(entry, "parent") is { } parentName
                ? (byName.TryGetValue(parentName, out var p)
                    ? p
                    : throw new InvalidDataException($"Node '{name}' references parent '{parentName}' that has not been declared yet (parents must come first)"))
                : null;

            var instance = CreateInstance(typeName);
            tree.AddNode(instance, name, parent);

            ApplyTransform(instance, entry);
            ApplyProperties(instance, entry);

            byName[name] = instance;
        }
    }

    // ── Type resolution ───────────────────────────────────────────────────────

    private static Node CreateInstance(string typeName)
    {
        var type = ResolveType(typeName);
        if (!typeof(Node).IsAssignableFrom(type))
            throw new InvalidDataException($"Type '{typeName}' is not a Node");

        var instance = Activator.CreateInstance(type)
            ?? throw new InvalidDataException($"Type '{typeName}' has no public parameterless constructor");
        return (Node)instance;
    }

    private static Type ResolveType(string typeName)
    {
        // Short name → assume KernelEngine.Framework namespace (built-ins).
        if (!typeName.Contains('.'))
        {
            var t = Type.GetType($"KernelEngine.Framework.{typeName}, KernelEngine.Framework");
            if (t != null) return t;
        }

        // FQN — try across loaded assemblies.
        var direct = Type.GetType(typeName);
        if (direct != null) return direct;

        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            var t = asm.GetType(typeName);
            if (t != null) return t;
        }
        throw new InvalidDataException($"Type '{typeName}' not found in any loaded assembly");
    }

    // ── Transform ─────────────────────────────────────────────────────────────

    private static void ApplyTransform(Node node, TomlTable entry)
    {
        if (!entry.TryGetValue("transform", out var raw) || raw is not TomlTable transform) return;

        var t = node.LocalTransform;
        if (transform.TryGetValue("position", out var p) && p is TomlArray pa)
            t = t with { Position = AsVector3(pa) };
        if (transform.TryGetValue("scale", out var s) && s is TomlArray sa)
            t = t with { Scale = AsVector3(sa) };
        if (transform.TryGetValue("rotation_euler", out var r) && r is TomlArray ra)
        {
            var euler = AsVector3(ra) * (MathF.PI / 180f);
            t = t with { Rotation = Quaternion.CreateFromYawPitchRoll(euler.Y, euler.X, euler.Z) };
        }
        else if (transform.TryGetValue("rotation", out var rq) && rq is TomlArray rqa && rqa.Count == 4)
        {
            t = t with { Rotation = AsQuaternion(rqa) };
        }
        node.LocalTransform = t;
    }

    // ── Properties (reflection) ───────────────────────────────────────────────

    private static void ApplyProperties(Node node, TomlTable entry)
    {
        if (!entry.TryGetValue("properties", out var raw) || raw is not TomlTable props) return;

        var type = node.GetType();
        foreach (var key in props.Keys)
        {
            var prop = type.GetProperty(key, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
            if (prop is null || !prop.CanWrite) continue;

            var value = props[key];
            try
            {
                prop.SetValue(node, Convert(value, prop.PropertyType));
            }
            catch (Exception ex)
            {
                throw new InvalidDataException(
                    $"Could not bind TOML value '{value}' to {type.Name}.{prop.Name} ({prop.PropertyType.Name}): {ex.Message}", ex);
            }
        }
    }

    private static object? Convert(object? raw, Type targetType)
    {
        if (raw is null) return null;
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;

        if (underlying == typeof(Vector2) && raw is TomlArray v2) return AsVector2(v2);
        if (underlying == typeof(Vector3) && raw is TomlArray v3) return AsVector3(v3);
        if (underlying == typeof(Vector4) && raw is TomlArray v4) return AsVector4(v4);
        if (underlying == typeof(Quaternion) && raw is TomlArray q) return AsQuaternion(q);

        if (underlying.IsInstanceOfType(raw)) return raw;

        if (underlying.IsEnum)
        {
            return raw switch
            {
                string s => Enum.Parse(underlying, s, ignoreCase: true),
                long l => Enum.ToObject(underlying, l),
                _ => Enum.ToObject(underlying, System.Convert.ToInt64(raw)),
            };
        }

        return System.Convert.ChangeType(raw, underlying, System.Globalization.CultureInfo.InvariantCulture);
    }

    // ── TOML helpers ──────────────────────────────────────────────────────────

    private static string? GetString(TomlTable t, string key)
        => t.TryGetValue(key, out var v) ? v as string : null;

    private static Vector2 AsVector2(TomlArray a) => new(F(a, 0), F(a, 1));
    private static Vector3 AsVector3(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2));
    private static Vector4 AsVector4(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));
    private static Quaternion AsQuaternion(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));

    private static float F(TomlArray a, int i)
    {
        var v = a[i];
        return v switch
        {
            long l => l,
            double d => (float)d,
            int n => n,
            float f => f,
            _ => System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture),
        };
    }
}
