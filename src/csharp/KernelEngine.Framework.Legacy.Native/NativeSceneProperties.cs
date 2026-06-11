using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Framework.Legacy.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Native-backed implementation of <see cref="ISceneProperties"/>. Wraps a pointer into the
/// SceneLoader-owned entry array (see <c>ke_scene_properties</c>) and decodes variants on
/// demand. All unsafe pointer work is confined to this class so the sugar layer can stay
/// <c>AllowUnsafeBlocks=false</c>.
/// </summary>
public sealed unsafe class NativeSceneProperties : ISceneProperties
{
    private readonly ke_scene_properties _bag;

    public NativeSceneProperties(ke_scene_properties bag) { _bag = bag; }

    public bool IsEmpty => _bag.entries == null || _bag.count == 0;

    // ── Resolver ────────────────────────────────────────────────────────────
    //
    // Look up the bag for an entity. Used by the framework's Node.Properties
    // accessor: caches the scene_properties cid on the world (first call does
    // the name lookup; subsequent calls reuse).

    private static readonly System.Collections.Generic.Dictionary<IWorld, uint?> s_cidCache = new();

    public static ISceneProperties For(IWorld world, ulong entity)
    {
        if (!s_cidCache.TryGetValue(world, out var cidOpt))
        {
            cidOpt = world.Registry.TryLookupComponent("scene_properties", out var c) ? c : null;
            s_cidCache[world] = cidOpt;
        }
        if (cidOpt is not uint cid) return EmptySceneProperties.Instance;

        var slot = world.Registry.GetComponent<ke_scene_properties>(entity, cid);
        if (slot.IsEmpty) return EmptySceneProperties.Instance;
        return new NativeSceneProperties(slot[0]);
    }

    // ── Variant lookup ──────────────────────────────────────────────────────

    private bool TryFind(string key, out ke_variant variant)
    {
        for (uint i = 0; i < _bag.count; i++)
        {
            var entry = &_bag.entries[i];
            var entryKey = Marshal.PtrToStringUTF8((IntPtr)entry->key);
            if (entryKey == key) { variant = entry->value; return true; }
        }
        variant = default;
        return false;
    }

    public bool TryGetString(string key, out string value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_STRING && v.s != null)
        {
            value = Marshal.PtrToStringUTF8((IntPtr)v.s) ?? "";
            return true;
        }
        value = "";
        return false;
    }

    public bool TryGetFloat(string key, out float value)
    {
        if (TryFind(key, out var v))
        {
            if (v.type == ke_variant_type.KE_VARIANT_FLOAT) { value = (float)v.f; return true; }
            if (v.type == ke_variant_type.KE_VARIANT_INT)   { value = v.i;        return true; }
        }
        value = 0f;
        return false;
    }

    public bool TryGetInt(string key, out long value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_INT)
        {
            value = v.i;
            return true;
        }
        value = 0;
        return false;
    }

    public bool TryGetBool(string key, out bool value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_BOOL)
        {
            value = v.b;
            return true;
        }
        value = false;
        return false;
    }

    public bool TryGetVector2(string key, out Vector2 value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_VEC2)
        {
            value = new Vector2(v.v2.x, v.v2.y);
            return true;
        }
        value = default;
        return false;
    }

    public bool TryGetVector3(string key, out Vector3 value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_VEC3)
        {
            value = new Vector3(v.v3.x, v.v3.y, v.v3.z);
            return true;
        }
        value = default;
        return false;
    }

    public bool TryGetVector4(string key, out Vector4 value)
    {
        if (TryFind(key, out var v) && v.type == ke_variant_type.KE_VARIANT_VEC4)
        {
            value = new Vector4(v.v4.x, v.v4.y, v.v4.z, v.v4.w);
            return true;
        }
        value = default;
        return false;
    }

    public string  GetString (string key, string  fallback = "")      => TryGetString (key, out var v) ? v : fallback;
    public float   GetFloat  (string key, float   fallback = 0f)      => TryGetFloat  (key, out var v) ? v : fallback;
    public long    GetInt    (string key, long    fallback = 0)       => TryGetInt    (key, out var v) ? v : fallback;
    public bool    GetBool   (string key, bool    fallback = false)   => TryGetBool   (key, out var v) ? v : fallback;
    public Vector2 GetVector2(string key, Vector2 fallback = default) => TryGetVector2(key, out var v) ? v : fallback;
    public Vector3 GetVector3(string key, Vector3 fallback = default) => TryGetVector3(key, out var v) ? v : fallback;
    public Vector4 GetVector4(string key, Vector4 fallback = default) => TryGetVector4(key, out var v) ? v : fallback;
}
