using System.Reflection;
using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Framework-side helpers that register C# <see cref="Node"/> subclasses with an
/// <see cref="INodeTypeRegistry"/>. Kept in Framework (not in the plugin) because it needs
/// access to <c>Node.Initialize</c> and the property-conversion logic from <c>SceneLoader</c>.
/// </summary>
public static class NodeTypeRegistrar
{
    /// <summary>
    /// Registers a C# <typeparamref name="T"/> node type under its short class name.
    /// <para>
    /// The <c>create</c> callback uses <see cref="ActivatorUtilities"/> when
    /// <paramref name="services"/> is provided, falling back to parameterless construction.
    /// The <c>setProperty</c> callback finds the node by entity and sets public properties
    /// via reflection (same logic as <c>SceneLoader.ApplyProperties</c>).
    /// </para>
    /// </summary>
    public static void Register<T>(
        this INodeTypeRegistry registry,
        IWorld world,
        IServiceProvider? services     = null,
        ResourceManager?  resources    = null,
        string?           typeNameOverride = null)
        where T : Node
    {
        var typeName = typeNameOverride ?? typeof(T).Name;

        registry.Register(
            typeName,
            create: (entity, name) =>
            {
                var node = services is not null
                    ? (T)ActivatorUtilities.CreateInstance(services, typeof(T))
                    : (T)Activator.CreateInstance(typeof(T))!;
                node.Initialize(entity, world, name);
            },
            setProperty: (entity, key, value) =>
            {
                var node = Node.FromEntity(entity);
                if (node == null) return;
                ApplyProperty(node, key, value, resources);
            });
    }

    // ── Type resolution (same logic as legacy SceneLoader.ResolveType) ─────────

    /// <summary>
    /// Resolves a Node subclass by short name or fully-qualified name across all loaded assemblies.
    /// Returns <c>null</c> if not found or if the type is not a <see cref="Node"/> subclass.
    /// </summary>
    public static Type? ResolveNodeType(string typeName)
    {
        if (!typeName.Contains('.'))
        {
            var t = Type.GetType($"KernelEngine.Framework.{typeName}, KernelEngine.Framework");
            if (t != null && typeof(Node).IsAssignableFrom(t)) return t;
        }

        var direct = Type.GetType(typeName);
        if (direct != null && typeof(Node).IsAssignableFrom(direct)) return direct;

        foreach (var asm in AppDomain.CurrentDomain.GetAssemblies())
        {
            var t = asm.GetType(typeName);
            if (t != null && typeof(Node).IsAssignableFrom(t)) return t;
        }
        return null;
    }

    // ── Property conversion (mirrors SceneLoader.Convert, no res:// here) ────

    internal static void ApplyProperty(Node node, string key, object? value, ResourceManager? resources)
    {
        var prop = node.GetType().GetProperty(
            key, BindingFlags.Public | BindingFlags.Instance | BindingFlags.IgnoreCase);
        if (prop is null || !prop.CanWrite) return;

        try
        {
            var converted = ConvertValue(value, prop.PropertyType, resources);
            prop.SetValue(node, converted);
        }
        catch (Exception ex)
        {
            throw new InvalidDataException(
                $"Could not bind value '{value}' to {node.GetType().Name}.{prop.Name}: {ex.Message}", ex);
        }
    }

    private static object? ConvertValue(object? raw, Type targetType, ResourceManager? resources)
    {
        if (raw is null) return null;
        var underlying = Nullable.GetUnderlyingType(targetType) ?? targetType;

        // Math types from TOML arrays (passed as Tomlyn.Model.TomlArray by the plugin).
        if (raw is Tomlyn.Model.TomlArray arr)
        {
            if (underlying == typeof(Vector2))     return AsVector2(arr);
            if (underlying == typeof(Vector3))     return AsVector3(arr);
            if (underlying == typeof(Vector4))     return AsVector4(arr);
            if (underlying == typeof(Quaternion))  return AsQuaternion(arr);
        }

        // Shape2D from TOML inline table.
        if (typeof(Shape2D).IsAssignableFrom(underlying) && raw is Tomlyn.Model.TomlTable shapeTable)
            return BuildShape(shapeTable);

        // Resource paths — resolved synchronously using ResourceManager.
        if (underlying == typeof(Mesh) || underlying == typeof(Material))
        {
            if (raw is string resPath && resPath.StartsWith("res://", StringComparison.Ordinal))
            {
                if (resources is null)
                    throw new InvalidOperationException(
                        $"Resource property requires ResourceManager; pass it to NodeTypeRegistrar.Register.");
                return ResolveResource(underlying, resPath, resources);
            }
        }

        // Direct type match.
        if (underlying.IsInstanceOfType(raw)) return raw;

        // Enum.
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

    // ── Shape2D ───────────────────────────────────────────────────────────────

    private static Shape2D BuildShape(Tomlyn.Model.TomlTable t)
    {
        var kind = GetString(t, "kind") ?? throw new InvalidDataException("Shape table missing 'kind'.");
        return kind switch
        {
            "rectangle" => new RectangleShape2D(
                t.TryGetValue("half_extents", out var he) && he is Tomlyn.Model.TomlArray hea
                    ? AsVector2(hea)
                    : throw new InvalidDataException("rectangle shape missing 'half_extents'.")),
            "circle" => new CircleShape2D(
                t.TryGetValue("radius", out var r) ? ToFloat(r)
                    : throw new InvalidDataException("circle shape missing 'radius'.")),
            _ => throw new InvalidDataException($"Unknown shape kind '{kind}'."),
        };
    }

    // ── Resource resolution ───────────────────────────────────────────────────

    private static object? ResolveResource(Type type, string resPath, ResourceManager resources)
    {
        const string primitivePrefix = "res://primitives/";
        if (type == typeof(Mesh) && resPath.StartsWith(primitivePrefix, StringComparison.Ordinal))
        {
            var name = resPath[primitivePrefix.Length..];
            MeshShape shape = name switch
            {
                "plane"  => MeshShape.Plane(),
                "cube"   => MeshShape.Cube(),
                "quad"   => MeshShape.Quad(),
                "sphere" => MeshShape.Sphere(32),
                _ => throw new InvalidDataException($"Unknown primitive '{name}'."),
            };
            return resources.CreateMeshAsync(shape).GetAwaiter().GetResult();
        }
        if (type == typeof(Material) && resPath.EndsWith(".material", StringComparison.Ordinal))
        {
            // Material resolution is complex (needs Tomlyn + ResourceManager). Delegate back to
            // SceneLoader helper to avoid duplication.
            return null; // TODO: extract ResolveMaterial from SceneLoader
        }
        throw new InvalidDataException($"Cannot resolve '{resPath}' as {type.Name}.");
    }

    // ── TOML helpers ──────────────────────────────────────────────────────────

    private static string? GetString(Tomlyn.Model.TomlTable t, string key)
        => t.TryGetValue(key, out var v) ? v as string : null;

    private static Vector2    AsVector2(Tomlyn.Model.TomlArray a) => new(F(a, 0), F(a, 1));
    private static Vector3    AsVector3(Tomlyn.Model.TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2));
    private static Vector4    AsVector4(Tomlyn.Model.TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));
    private static Quaternion AsQuaternion(Tomlyn.Model.TomlArray a) => new(F(a, 0), F(a, 1), F(a, 2), F(a, 3));

    private static float F(Tomlyn.Model.TomlArray a, int i) => ToFloat(a[i]);

    private static float ToFloat(object? v) => v switch
    {
        long l   => l,
        double d => (float)d,
        int n    => n,
        float f  => f,
        _ => System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture),
    };
}
