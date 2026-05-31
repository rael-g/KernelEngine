using System.Numerics;
using System.Text;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.CSharp;

/// <summary>
/// C# plugin implementation of <see cref="ISceneLoader"/>.
/// <para>
/// Parses <c>*.scene.toml</c> files and instantiates nodes through <see cref="INodeTypeRegistry"/>
/// — no reflection, no Framework types. Node creation and property setting are delegated to
/// binding-registered callbacks (Framework registers C# <c>Node</c> subclasses; a future Lua
/// binding registers Lua table factories using the same interface).
/// </para>
/// <para>
/// Hierarchy is built directly via <see cref="IEcsRegistry"/> using the kernel component IDs
/// exposed by <see cref="IWorld"/>. This keeps the logic identical to what a future C++ plugin
/// would do.
/// </para>
/// </summary>
internal sealed class CSharpSceneLoader : ISceneLoader
{
    private readonly IWorld _world;
    private readonly INodeTypeRegistry _registry;

    public CSharpSceneLoader(IWorld world, INodeTypeRegistry registry)
    {
        _world    = world;
        _registry = registry;
    }

    // ── ISceneLoader ──────────────────────────────────────────────────────────

    public Task LoadAsync(string path) =>
        LoadScene(path, attachParentEntity: 0, rootNameOverride: null, rootEntryOverride: null);

    // ── Core ──────────────────────────────────────────────────────────────────

    private Task LoadScene(string path,
        ulong attachParentEntity, string? rootNameOverride, TomlTable? rootEntryOverride)
    {
        if (!File.Exists(path))
            throw new FileNotFoundException($"Scene file not found: {path}");

        var doc = Toml.ToModel(File.ReadAllText(path));
        if (!doc.TryGetValue("node", out var rawNodes) || rawNodes is not TomlTableArray nodes)
            return Task.CompletedTask;

        var byName  = new Dictionary<string, ulong>(StringComparer.Ordinal);
        bool isFirst = true;

        foreach (var entry in nodes)
        {
            var innerName = GetString(entry, "name");
            var typeName  = GetString(entry, "type");
            var sceneRef  = GetString(entry, "scene");

            var parentName   = GetString(entry, "parent");
            ulong parentEntity = parentName is not null
                ? (byName.TryGetValue(parentName, out var p)
                    ? p
                    : throw new InvalidDataException(
                        $"Node '{innerName}' references parent '{parentName}' that has not been declared yet."))
                : (isFirst ? attachParentEntity : 0);

            var effectiveName = (isFirst && rootNameOverride != null) ? rootNameOverride : innerName;

            ulong entity;
            if (sceneRef != null)
            {
                // Nested scene — recurse. Outer entry's name + properties override the inner root.
                LoadScene(ResolveScenePath(sceneRef), parentEntity, effectiveName, entry)
                    .GetAwaiter().GetResult();

                // The inner root entity is the first entity created by the recursion.
                // For parent linking of outer siblings, use the name that the inner root was assigned.
                if (effectiveName is not null && byName.TryGetValue(effectiveName, out var innerRoot))
                    entity = innerRoot;
                else
                    entity = 0;
            }
            else
            {
                if (typeName is null)
                    throw new InvalidDataException("[[node]] entry needs either 'type' or 'scene'.");
                if (effectiveName is null)
                    throw new InvalidDataException("[[node]] entry missing 'name'.");

                entity = CreateEntity(effectiveName, parentEntity);

                if (!_registry.TryCreate(typeName, entity, effectiveName))
                    throw new InvalidDataException(
                        $"Node type '{typeName}' is not registered. Call INodeTypeRegistry.Register before loading scenes that reference it.");

                ApplyTransform(entity, entry);
                ApplyProperties(typeName, entity, entry);

                if (isFirst && rootEntryOverride != null)
                {
                    ApplyTransform(entity, rootEntryOverride);
                    ApplyProperties(typeName, entity, rootEntryOverride);
                }
            }

            if (innerName is not null && entity != 0)
                byName[innerName] = entity;

            isFirst = false;
        }

        return Task.CompletedTask;
    }

    // ── Entity + hierarchy ────────────────────────────────────────────────────

    private ulong CreateEntity(string name, ulong parentEntity)
    {
        var reg    = _world.Registry;
        var entity = reg.CreateEntity();

        // Transform — default: origin, identity rotation, unit scale.
        var t = reg.AddComponent<ke_transform_component>(entity, _world.TransformComponentId);
        t[0] = new ke_transform_component
        {
            position     = new ke_vec3 { x = 0, y = 0, z = 0 },
            rotation     = new ke_quat { x = 0, y = 0, z = 0, w = 1 },
            scale        = new ke_vec3 { x = 1, y = 1, z = 1 },
            world_matrix = IdentityMatrix(),
        };

        // Hierarchy.
        var h = reg.AddComponent<ke_hierarchy_component>(entity, _world.HierarchyComponentId);
        h[0] = new ke_hierarchy_component { parent = parentEntity };

        // Prepend into parent's child list (O(1) doubly-linked prepend).
        if (parentEntity != 0)
        {
            var ph = reg.GetComponent<ke_hierarchy_component>(parentEntity, _world.HierarchyComponentId);
            if (!ph.IsEmpty)
            {
                h[0].next_sibling = ph[0].first_child;
                if (ph[0].first_child != 0)
                {
                    var sib = reg.GetComponent<ke_hierarchy_component>(ph[0].first_child, _world.HierarchyComponentId);
                    if (!sib.IsEmpty) sib[0].prev_sibling = entity;
                }
                ph[0].first_child = entity;
            }
        }

        // Name.
        var n = reg.AddComponent<ke_name_component>(entity, _world.NameComponentId);
        SetName(ref n[0], name);

        return entity;
    }

    private static ke_mat4 IdentityMatrix()
    {
        var m = new ke_mat4();
        m.m[0] = m.m[5] = m.m[10] = m.m[15] = 1f;
        return m;
    }

    private static unsafe void SetName(ref ke_name_component comp, string name)
    {
        if (string.IsNullOrEmpty(name)) return;
        var bytes = Encoding.UTF8.GetBytes(name);
        int len   = Math.Min(bytes.Length, 63);
        // comp.name is a fixed sbyte[64] inline array.
        comp.name[0] = 0; // zero first to ensure null-termination on empty
        for (int i = 0; i < len; i++) comp.name[i] = (sbyte)bytes[i];
        comp.name[len] = 0;
    }

    // ── Transform ─────────────────────────────────────────────────────────────

    private void ApplyTransform(ulong entity, TomlTable entry)
    {
        if (!entry.TryGetValue("transform", out var raw) || raw is not TomlTable transform) return;

        var slot = _world.Registry.GetComponent<ke_transform_component>(entity, _world.TransformComponentId);
        if (slot.IsEmpty) return;

        ref var t = ref slot[0];
        if (transform.TryGetValue("position", out var p) && p is TomlArray pa)
            t.position = AsVec3(pa);
        if (transform.TryGetValue("scale", out var s) && s is TomlArray sa)
            t.scale = AsVec3(sa);
        if (transform.TryGetValue("rotation_euler", out var r) && r is TomlArray ra)
        {
            var euler = AsVec3(ra);
            var q     = Quaternion.CreateFromYawPitchRoll(
                euler.y * (MathF.PI / 180f),
                euler.x * (MathF.PI / 180f),
                euler.z * (MathF.PI / 180f));
            t.rotation = new ke_quat { x = q.X, y = q.Y, z = q.Z, w = q.W };
        }
        else if (transform.TryGetValue("rotation", out var rq) && rq is TomlArray rqa && rqa.Count == 4)
        {
            t.rotation = new ke_quat
                { x = F(rqa, 0), y = F(rqa, 1), z = F(rqa, 2), w = F(rqa, 3) };
        }
    }

    // ── Properties ────────────────────────────────────────────────────────────

    private void ApplyProperties(string typeName, ulong entity, TomlTable entry)
    {
        if (!entry.TryGetValue("properties", out var raw) || raw is not TomlTable props) return;

        foreach (var key in props.Keys)
            _registry.TrySetProperty(typeName, entity, key, props[key]);
    }

    // ── Path helpers ──────────────────────────────────────────────────────────

    private static string ResolveScenePath(string resPath)
    {
        const string prefix = "res://";
        if (!resPath.StartsWith(prefix, StringComparison.Ordinal))
            throw new InvalidDataException($"Scene reference '{resPath}' must start with 'res://'.");
        return Path.Combine(AppContext.BaseDirectory, resPath[prefix.Length..]);
    }

    // ── TOML helpers ──────────────────────────────────────────────────────────

    private static string? GetString(TomlTable t, string key)
        => t.TryGetValue(key, out var v) ? v as string : null;

    private static ke_vec3 AsVec3(TomlArray a) =>
        new() { x = F(a, 0), y = F(a, 1), z = F(a, 2) };

    private static float F(TomlArray a, int i) => ToFloat(a[i]);

    private static float ToFloat(object? v) => v switch
    {
        long l   => l,
        double d => (float)d,
        int n    => n,
        float f  => f,
        _ => System.Convert.ToSingle(v, System.Globalization.CultureInfo.InvariantCulture),
    };
}
