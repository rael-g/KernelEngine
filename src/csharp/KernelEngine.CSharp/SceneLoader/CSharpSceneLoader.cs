using System.Numerics;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Tomlyn;
using Tomlyn.Model;

namespace KernelEngine.CSharp;

/// <summary>
/// C# plugin implementation of <see cref="ISceneLoader"/>.
/// <para>
/// Parses <c>*.scene.toml</c> files and instantiates nodes through <see cref="INodeTypeRegistry"/>
/// — no reflection, no Framework types. Entity creation and hierarchy management are delegated to
/// <see cref="ISceneTree.CreateNode"/>, keeping the loader decoupled from raw ECS.
/// </para>
/// </summary>
internal sealed class CSharpSceneLoader : ISceneLoader
{
    private readonly IWorld _world;
    private readonly INodeTypeRegistry _registry;
    private readonly ISceneTree _tree;

    public CSharpSceneLoader(IWorld world, INodeTypeRegistry registry, ISceneTree tree)
    {
        _world    = world;
        _registry = registry;
        _tree     = tree;
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
                LoadScene(ResolveScenePath(sceneRef), parentEntity, effectiveName, entry)
                    .GetAwaiter().GetResult();

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

                // Delegate hierarchy creation to ISceneTree — it handles linking correctly.
                entity = _tree.CreateNode(effectiveName, parentEntity);

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
