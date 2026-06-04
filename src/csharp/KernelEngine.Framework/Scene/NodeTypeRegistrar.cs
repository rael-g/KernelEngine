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
    /// Active asset resolver. Set by <see cref="Application"/> at startup so the property binder
    /// can use it to resolve <c>res://*.material</c> references through the native
    /// <c>ke_asset_resolver</c> plugin. Tests may set this directly.
    /// </summary>
    internal static IAssetResolverBackend? ActiveAssetResolver { get; set; }

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

        // Math types from the native scene loader (ke_vec2/3/4 structs).
        if (raw is KernelEngine.Kernel.Native.ke_vec2 v2 && underlying == typeof(Vector2)) return new Vector2(v2.x, v2.y);
        if (raw is KernelEngine.Kernel.Native.ke_vec3 v3)
        {
            if (underlying == typeof(Vector3)) return new Vector3(v3.x, v3.y, v3.z);
            if (underlying == typeof(Vector4)) return new Vector4(v3.x, v3.y, v3.z, 1f);
        }
        if (raw is KernelEngine.Kernel.Native.ke_vec4 v4)
        {
            if (underlying == typeof(Vector4))    return new Vector4(v4.x, v4.y, v4.z, v4.w);
            if (underlying == typeof(Quaternion)) return new Quaternion(v4.x, v4.y, v4.z, v4.w);
        }

        // Shape2D from TOML inline table.
        if (typeof(Shape2D).IsAssignableFrom(underlying) && raw is Tomlyn.Model.TomlTable shapeTable)
            return BuildShape(shapeTable);
        if (typeof(Shape2D).IsAssignableFrom(underlying) && raw is IDictionary<string, object?> shapeDict)
            return BuildShapeFromDict(shapeDict);

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
            // Inline material table: { base_color = [r,g,b,a] }
            if (underlying == typeof(Material) && raw is Tomlyn.Model.TomlTable matTable)
            {
                if (resources is null)
                    throw new InvalidOperationException(
                        $"Resource property requires ResourceManager; pass it to NodeTypeRegistrar.Register.");
                return BuildInlineMaterial(matTable, resources);
            }
            // Inline material from native ke_variant_table (scene loader path).
            if (underlying == typeof(Material) && raw is IDictionary<string, object?> matDict)
            {
                if (resources is null)
                    throw new InvalidOperationException(
                        $"Resource property requires ResourceManager; pass it to NodeTypeRegistrar.Register.");
                return BuildInlineMaterialFromDict(matDict, resources);
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
        if (type == typeof(Mesh) && resPath.StartsWith("res://primitives/", StringComparison.Ordinal))
        {
            var resolver = ActiveAssetResolver
                ?? throw new InvalidOperationException(
                    "Mesh primitive resolution requires an asset resolver backend. " +
                    "Call services.AddNativeFramework() before scene loading.");
            var buffer = resolver.ResolveMesh(resPath)
                ?? throw new InvalidDataException($"Unknown primitive '{resPath}'.");
            return resources.CreateMeshAsync(buffer.Vertices, buffer.Indices).GetAwaiter().GetResult();
        }
        if (type == typeof(Material) && resPath.EndsWith(".material", StringComparison.Ordinal))
        {
            // Native ke_asset_resolver parses the [material] TOML section into a spec; we then
            // build the GPU material via ResourceManager. Texture references are deferred
            // (left as paths in the spec) until the resolver also bridges resolve_texture.
            var resolver = ActiveAssetResolver
                ?? throw new InvalidOperationException(
                    "Material file resolution requires an asset resolver. " +
                    "Run inside Application or call NodeTypeRegistrar.SetActiveAssetResolver(...).");
            var spec = resolver.ResolveMaterial(resPath)
                ?? throw new InvalidDataException($"Material file '{resPath}' not found.");
            return resources.CreateMaterialAsync(
                spec.BaseColor,
                metallic:  spec.Metallic,
                roughness: spec.Roughness).GetAwaiter().GetResult();
        }
        throw new InvalidDataException($"Cannot resolve '{resPath}' as {type.Name}.");
    }

    private static Material BuildInlineMaterial(Tomlyn.Model.TomlTable t, ResourceManager resources)
    {
        var color = t.TryGetValue("base_color", out var bc) && bc is Tomlyn.Model.TomlArray bca
            ? new System.Numerics.Vector4(F(bca, 0), F(bca, 1), F(bca, 2), F(bca, 3))
            : System.Numerics.Vector4.One;
        var metallic  = t.TryGetValue("metallic",  out var m) ? ToFloat(m) : 0f;
        var roughness = t.TryGetValue("roughness",  out var r) ? ToFloat(r) : 0.5f;
        return resources.CreateMaterialAsync(color, metallic: metallic, roughness: roughness)
            .GetAwaiter().GetResult();
    }

    // Dict variant — called when the native ke_scene_loader unpacks an inline table into
    // KE_VARIANT_TABLE (NodeTypeRegistry.VariantToObject materialises it as a Dictionary).
    // ke_variant arrays of length 4 already become Vector4 on the C# side, so the base_color
    // entry arrives as a Vector4 here, not an array.
    private static Material BuildInlineMaterialFromDict(IDictionary<string, object?> d, ResourceManager resources)
    {
        var color = d.TryGetValue("base_color", out var bc) ? ToVector4(bc) : System.Numerics.Vector4.One;
        var metallic  = d.TryGetValue("metallic",  out var m) ? ToFloat(m) : 0f;
        var roughness = d.TryGetValue("roughness", out var r) ? ToFloat(r) : 0.5f;
        return resources.CreateMaterialAsync(color, metallic: metallic, roughness: roughness)
            .GetAwaiter().GetResult();
    }

    private static Shape2D BuildShapeFromDict(IDictionary<string, object?> d)
    {
        var kind = d.TryGetValue("kind", out var k) ? k as string : null;
        if (kind is null) throw new InvalidDataException("Shape table missing 'kind'.");
        return kind switch
        {
            "rectangle" => new RectangleShape2D(
                d.TryGetValue("half_extents", out var he) ? ToVector2(he)
                    : throw new InvalidDataException("rectangle shape missing 'half_extents'.")),
            "circle" => new CircleShape2D(
                d.TryGetValue("radius", out var rv) ? ToFloat(rv)
                    : throw new InvalidDataException("circle shape missing 'radius'.")),
            _ => throw new InvalidDataException($"Unknown shape kind '{kind}'."),
        };
    }

    private static Vector4 ToVector4(object? raw) => raw switch
    {
        Vector4 v                                       => v,
        Vector3 v3                                      => new Vector4(v3, 1f),
        KernelEngine.Kernel.Native.ke_vec4 nv4          => new Vector4(nv4.x, nv4.y, nv4.z, nv4.w),
        KernelEngine.Kernel.Native.ke_vec3 nv3          => new Vector4(nv3.x, nv3.y, nv3.z, 1f),
        Tomlyn.Model.TomlArray arr                      => new Vector4(F(arr, 0), F(arr, 1), F(arr, 2), F(arr, 3)),
        _                                               => System.Numerics.Vector4.One,
    };

    private static Vector2 ToVector2(object? raw) => raw switch
    {
        Vector2 v                                       => v,
        KernelEngine.Kernel.Native.ke_vec2 nv2          => new Vector2(nv2.x, nv2.y),
        Tomlyn.Model.TomlArray arr                      => new Vector2(F(arr, 0), F(arr, 1)),
        _                                               => Vector2.Zero,
    };

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
