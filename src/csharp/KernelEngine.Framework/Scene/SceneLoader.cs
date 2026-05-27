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
/// than its children.
/// </para>
///
/// <para>
/// Resource references (<c>"res://..."</c> strings on <see cref="Mesh"/>/<see cref="Material"/>
/// properties) are resolved by <see cref="LoadAsync"/>. The sync <see cref="Load"/> entry point
/// throws on res:// strings since async loaders cannot block the calling thread safely.
/// </para>
///
/// <para>
/// A resource-typed property (<see cref="Mesh"/>, <see cref="Material"/>) accepts either:
/// </para>
/// <list type="bullet">
///   <item>A <c>"res://..."</c> string — load from a file (reusable across scenes).</item>
///   <item>An inline TOML table — define right here (one-off, no separate file). Inline applies
///   to types that are pure data (Material today); meshes stay path-based since vertex data
///   does not belong in a scene file.</item>
/// </list>
///
/// <para>
/// Supported res:// schemes in this slice:
/// </para>
/// <list type="bullet">
///   <item><c>res://primitives/{plane|cube|quad|sphere}</c> — built-in <see cref="MeshShape"/> primitives.</item>
///   <item><c>res://path/to/X.material</c> — material manifest (base_color, metallic, roughness; textures deferred to next slice).</item>
/// </list>
/// </summary>
public static class SceneLoader
{
    /// <summary>
    /// Synchronous load — accepts scenes that do not reference resources via <c>res://</c>.
    /// Use <see cref="LoadAsync"/> when properties bind to <see cref="Mesh"/>/<see cref="Material"/> by path.
    /// </summary>
    public static void Load(Tree tree, string path)
    {
        LoadCore(tree, path, resources: null).GetAwaiter().GetResult();
    }

    /// <summary>
    /// Async load — resolves <c>res://</c> references on resource properties through
    /// <paramref name="resources"/>. Awaitable; the typical caller is <c>OnReady</c>.
    /// </summary>
    public static Task LoadAsync(Tree tree, string path, ResourceManager resources)
    {
        return LoadCore(tree, path, resources);
    }

    // ── Core ──────────────────────────────────────────────────────────────────

    private static async Task LoadCore(Tree tree, string path, ResourceManager? resources)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"Scene file not found: {path}");

        var doc = Toml.ToModel(File.ReadAllText(path));
        if (!doc.TryGetValue("node", out var rawNodes) || rawNodes is not TomlTableArray nodes)
            return; // empty scene

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
            await ApplyProperties(instance, entry, resources);

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

    private static async Task ApplyProperties(Node node, TomlTable entry, ResourceManager? resources)
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
                object? converted;
                if (IsResourceType(prop.PropertyType))
                {
                    if (resources is null)
                        throw new InvalidOperationException($"Scene references a resource on {type.Name}.{prop.Name} but loader is sync; call SceneLoader.LoadAsync(tree, path, resources) instead.");
                    converted = await ResolveResourceFromAny(prop.PropertyType, value, resources);
                }
                else
                {
                    converted = Convert(value, prop.PropertyType);
                }
                prop.SetValue(node, converted);
            }
            catch (Exception ex) when (ex is not InvalidOperationException)
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

    // ── Resource resolution (res:// path OR inline table) ────────────────────

    private static bool IsResourceType(Type t) =>
        t == typeof(Mesh) || t == typeof(Material);

    private static Task<object?> ResolveResourceFromAny(Type type, object? raw, ResourceManager resources)
    {
        if (raw is string s && s.StartsWith("res://", StringComparison.Ordinal))
            return ResolveResource(type, s, resources);
        if (raw is TomlTable inline)
            return ResolveInlineResource(type, inline, resources);
        throw new InvalidDataException($"Resource of type {type.Name} must be a 'res://' path or an inline table; got {raw?.GetType().Name ?? "null"}");
    }

    private static async Task<object?> ResolveInlineResource(Type type, TomlTable inline, ResourceManager resources)
    {
        if (type == typeof(Material)) return await BuildMaterial(inline, resources);
        throw new InvalidDataException($"Inline definition of {type.Name} is not supported (use res:// instead)");
    }

    private static Task<object?> ResolveResource(Type type, string resPath, ResourceManager resources)
    {
        if (type == typeof(Mesh))     return ResolveMesh(resPath, resources);
        if (type == typeof(Material)) return ResolveMaterial(resPath, resources);
        throw new InvalidDataException($"Don't know how to resolve '{type.Name}' from {resPath} (only Mesh and Material supported in this slice)");
    }

    private static async Task<object?> ResolveMesh(string resPath, ResourceManager resources)
    {
        const string primitivePrefix = "res://primitives/";
        if (!resPath.StartsWith(primitivePrefix, StringComparison.Ordinal))
            throw new InvalidDataException($"Mesh path '{resPath}' is not recognized (only {primitivePrefix}{{plane|cube|quad|sphere}} supported in this slice)");

        var name = resPath[primitivePrefix.Length..];
        MeshShape shape = name switch
        {
            "plane"  => MeshShape.Plane(),
            "cube"   => MeshShape.Cube(),
            "quad"   => MeshShape.Quad(),
            "sphere" => MeshShape.Sphere(32),
            _ => throw new InvalidDataException($"Unknown primitive '{name}' (known: plane, cube, quad, sphere)"),
        };
        return await resources.CreateMeshAsync(shape);
    }

    private static async Task<object?> ResolveMaterial(string resPath, ResourceManager resources)
    {
        if (!resPath.EndsWith(".material", StringComparison.Ordinal))
            throw new InvalidDataException($"Material path '{resPath}' must end with .material");

        var relative = resPath["res://".Length..];
        var absolute = Path.Combine(AppContext.BaseDirectory, relative);
        if (!File.Exists(absolute))
            throw new FileNotFoundException($"Material file not found: {absolute} (referenced as {resPath})");

        var doc = Toml.ToModel(File.ReadAllText(absolute));
        if (!doc.TryGetValue("material", out var rawMat) || rawMat is not TomlTable mat)
            throw new InvalidDataException($"Material file {resPath} missing [material] section");

        return await BuildMaterial(mat, resources);
    }

    private static async Task<Material> BuildMaterial(TomlTable mat, ResourceManager resources)
    {
        var baseColor = mat.TryGetValue("base_color", out var bc) && bc is TomlArray bca
            ? AsVector4(bca)
            : new Vector4(1, 1, 1, 1);
        var metallic  = mat.TryGetValue("metallic",  out var m) ? ToFloat(m) : 0f;
        var roughness = mat.TryGetValue("roughness", out var r) ? ToFloat(r) : 0.5f;
        return await resources.CreateMaterialAsync(baseColor, metallic: metallic, roughness: roughness);
    }

    // ── TOML helpers ──────────────────────────────────────────────────────────

    private static string? GetString(TomlTable t, string key)
        => t.TryGetValue(key, out var v) ? v as string : null;

    private static Vector2 AsVector2(TomlArray a) => new(F(a, 0), F(a, 1));
    private static Vector3 AsVector3(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2));
    private static Vector4 AsVector4(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));
    private static Quaternion AsQuaternion(TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));

    private static float F(TomlArray a, int i) => ToFloat(a[i]);

    private static float ToFloat(object? v) => v switch
    {
        long l => l,
        double d => (float)d,
        int n => n,
        float f => f,
        _ => System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture),
    };
}
