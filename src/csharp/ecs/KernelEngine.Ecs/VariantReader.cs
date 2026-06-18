using System.Numerics;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Read-only view over a native variant-entry table, supplied to
/// <see cref="ComponentApplyCallback{T}"/> implementations. Abstracts the
/// unsafe C layout so game/framework code can read component fields without
/// requiring <c>AllowUnsafeBlocks</c>.
/// </summary>
/// <remarks>
/// This is a <see langword="ref struct"/>: it may only live on the stack and
/// must not be stored. It is valid only for the duration of the apply callback.
/// </remarks>
public ref struct VariantReader
{
    private readonly nint _entries; // ke_variant_table_entry* stored as nint
    private readonly uint _count;

    public unsafe VariantReader(ke_variant_table_entry* entries, uint count)
    {
        _entries = (nint)entries;
        _count   = count;
    }

    /// <summary>Number of entries in the table.</summary>
    public int Count => (int)_count;

    /// <summary>Returns the string value for <paramref name="key"/>, or <see langword="false"/> if absent or not a string.</summary>
    public unsafe bool TryGetString(string key, out string? value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_STRING && KeyEquals(e.key, key))
            {
                value = Marshal.PtrToStringAnsi((nint)e.value.s);
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the float value for <paramref name="key"/>, or <see langword="false"/> if absent or not numeric.</summary>
    public unsafe bool TryGetFloat(string key, out float value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_FLOAT && KeyEquals(e.key, key))
            {
                value = (float)e.value.f;
                return true;
            }
            if (e.value.type == ke_variant_type.KE_VARIANT_INT && KeyEquals(e.key, key))
            {
                value = e.value.i;
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the integer value for <paramref name="key"/>, or <see langword="false"/> if absent or not numeric.</summary>
    public unsafe bool TryGetInt(string key, out long value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_INT && KeyEquals(e.key, key))
            {
                value = e.value.i;
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the boolean value for <paramref name="key"/>, or <see langword="false"/> if absent or not a bool.</summary>
    public unsafe bool TryGetBool(string key, out bool value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_BOOL && KeyEquals(e.key, key))
            {
                value = e.value.b;
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the <see cref="Vector2"/> value for <paramref name="key"/>, or <see langword="false"/> if absent or wrong type.</summary>
    public unsafe bool TryGetVec2(string key, out Vector2 value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_VEC2 && KeyEquals(e.key, key))
            {
                value = new Vector2(e.value.v2.x, e.value.v2.y);
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the <see cref="Vector3"/> value for <paramref name="key"/>, or <see langword="false"/> if absent or wrong type.</summary>
    public unsafe bool TryGetVec3(string key, out Vector3 value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_VEC3 && KeyEquals(e.key, key))
            {
                value = new Vector3(e.value.v3.x, e.value.v3.y, e.value.v3.z);
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the <see cref="Vector4"/> value for <paramref name="key"/>, or <see langword="false"/> if absent or wrong type.</summary>
    public unsafe bool TryGetVec4(string key, out Vector4 value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_VEC4 && KeyEquals(e.key, key))
            {
                value = new Vector4(e.value.v4.x, e.value.v4.y, e.value.v4.z, e.value.v4.w);
                return true;
            }
        }
        value = default;
        return false;
    }

    /// <summary>Returns the <see cref="Quaternion"/> value for <paramref name="key"/>, or <see langword="false"/> if absent or wrong type.</summary>
    public unsafe bool TryGetQuat(string key, out Quaternion value)
    {
        var entries = (ke_variant_table_entry*)_entries;
        for (uint i = 0; i < _count; i++)
        {
            ref var e = ref entries[i];
            if (e.value.type == ke_variant_type.KE_VARIANT_QUAT && KeyEquals(e.key, key))
            {
                value = new Quaternion(e.value.q.x, e.value.q.y, e.value.q.z, e.value.q.w);
                return true;
            }
        }
        value = default;
        return false;
    }

    private static unsafe bool KeyEquals(sbyte* nativeKey, string key)
        => Marshal.PtrToStringAnsi((nint)nativeKey) == key;
}
