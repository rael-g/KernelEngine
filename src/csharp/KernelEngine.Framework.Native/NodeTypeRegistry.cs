using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel;
using KernelEngine.Framework.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Implements <see cref="INodeTypeRegistry"/> over the native <c>ke_node_type_registry</c>.
/// <para>
/// Each binding registers its node types with plain C# delegates (<c>create</c> /
/// <c>setProperty</c>). The registry wires the native vtable for C / Lua / C++ callers while
/// also providing a fast managed path (<see cref="TryCreate"/> / <see cref="TrySetProperty"/>)
/// that skips the ke_variant round-trip entirely for C# callers.
/// </para>
/// </summary>
public sealed unsafe class NodeTypeRegistry : INodeTypeRegistry, IDisposable
{
    // ── Per-type entry ────────────────────────────────────────────────────────────────────

    private sealed class TypeEntry
    {
        public required Action<ulong, string>           Create      { get; init; }
        public required Action<ulong, string, object?>  SetProperty { get; init; }
    }

    // ── State ─────────────────────────────────────────────────────────────────────────────

    // Managed fast-path: name → delegates. Bypasses ke_variant round-trip for C# callers.
    private readonly Dictionary<string, TypeEntry> _managed =
        new(StringComparer.Ordinal);

    // Fallback: called when a type name is not in _managed.
    private Func<string, ulong, string, bool>?          _fallbackCreate;
    private Func<string, ulong, string, object?, bool>? _fallbackSetProperty;

    // GCHandles kept alive so trampolines can resolve ctx → TypeEntry.
    private readonly List<GCHandle> _handles = [];
    // Unmanaged name strings (registry stores the pointer — we own the lifetime).
    private readonly List<nint> _nameStrings = [];

    private ke_node_type_registry* _native;

    /// <summary>Engine-internal: raw pointer for plugins (scene loader, etc.) that need the C handle.</summary>
    internal ke_node_type_registry* Native => _native;

    // ── Construction ──────────────────────────────────────────────────────────────────────

    public NodeTypeRegistry(Allocator allocator)
    {
        ke_node_type_registry* reg;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Native.NativeMethods.node_type_registry_create(allocator.Native, &reg).ToManaged());
        _native = reg;
    }

    // ── INodeTypeRegistry ────────────────────────────────────────────────────────────────

    /// <inheritdoc/>
    public void Register(string typeName,
        Action<ulong, string>          create,
        Action<ulong, string, object?> setProperty)
    {
        ArgumentNullException.ThrowIfNull(typeName);
        ArgumentNullException.ThrowIfNull(create);
        ArgumentNullException.ThrowIfNull(setProperty);

        var entry = new TypeEntry { Create = create, SetProperty = setProperty };
        _managed[typeName] = entry;

        var handle  = GCHandle.Alloc(entry);
        _handles.Add(handle);

        var namePtr = Marshal.StringToCoTaskMemUTF8(typeName);
        _nameStrings.Add(namePtr);

        var descriptor = new ke_node_type
        {
            name         = (sbyte*)namePtr,
            ctx          = (void*)GCHandle.ToIntPtr(handle),
            create       = &NativeCreate,
            set_property = &NativeSetProperty,
        };

        KernelException.ThrowIfFailed(
            _native->register_type(_native, &descriptor).ToManaged());
    }

    /// <inheritdoc/>
    public bool TryCreate(string typeName, ulong entity, string name)
    {
        if (_managed.TryGetValue(typeName, out var entry))
        {
            entry.Create(entity, name);
            return true;
        }
        return _fallbackCreate?.Invoke(typeName, entity, name) ?? false;
    }

    /// <inheritdoc/>
    public bool TrySetProperty(string typeName, ulong entity, string key, object? value)
    {
        if (_managed.TryGetValue(typeName, out var entry))
        {
            entry.SetProperty(entity, key, value);
            return true;
        }
        return _fallbackSetProperty?.Invoke(typeName, entity, key, value) ?? false;
    }

    /// <inheritdoc/>
    public void SetFallback(
        Func<string, ulong, string, bool>           tryCreate,
        Func<string, ulong, string, object?, bool>  trySetProperty)
    {
        _fallbackCreate      = tryCreate;
        _fallbackSetProperty = trySetProperty;

        // Bridge to the C plugin's lookup-miss callback so non-managed callers
        // (ke_scene_loader, future Lua binding) also benefit from on-demand resolution.
        var selfHandle = GCHandle.Alloc(this);
        _handles.Add(selfHandle);
        _native->set_lookup_miss(_native, &NativeLookupMiss, (void*)GCHandle.ToIntPtr(selfHandle));
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeLookupMiss(void* ctx, void* registry, sbyte* name)
    {
        try
        {
            var self    = (NodeTypeRegistry)GCHandle.FromIntPtr((nint)ctx).Target!;
            var typeStr = Marshal.PtrToStringUTF8((nint)name);
            if (typeStr is null || self._fallbackCreate is null || self._fallbackSetProperty is null)
                return ke_result.KE_ERROR_NOT_FOUND;

            // Register an on-the-fly entry that forwards to the fallback delegates.
            var fallbackCreate      = self._fallbackCreate;
            var fallbackSetProperty = self._fallbackSetProperty;
            string captured         = typeStr;

            self.Register(typeStr,
                create: (entity, n) =>
                {
                    if (!fallbackCreate(captured, entity, n))
                        throw new InvalidDataException($"Node type '{captured}' could not be resolved.");
                },
                setProperty: (entity, key, value) => fallbackSetProperty(captured, entity, key, value));
            return ke_result.KE_OK;
        }
        catch { return ke_result.KE_ERROR; }
    }

    // ── Trampolines (for C / Lua / C++ callers that go through the native vtable) ─────────

    /// <summary>
    /// Captures a managed exception thrown inside a native trampoline so the calling C# code
    /// (typically <see cref="NativeSceneLoader.Load"/>) can rethrow it after the native call
    /// unwinds. <c>[UnmanagedCallersOnly]</c> methods are not allowed to let exceptions cross
    /// the ABI; we surface them out-of-band instead.
    /// </summary>
    [ThreadStatic] internal static Exception? PendingTrampolineException;

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeCreate(void* ctx, ulong entity, sbyte* name)
    {
        try
        {
            var entry   = (TypeEntry)GCHandle.FromIntPtr((nint)ctx).Target!;
            var nameStr = Marshal.PtrToStringUTF8((nint)name) ?? string.Empty;
            entry.Create(entity, nameStr);
            return ke_result.KE_OK;
        }
        catch (Exception ex)
        {
            PendingTrampolineException ??= ex;
            return ke_result.KE_ERROR;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeSetProperty(void* ctx, ulong entity, sbyte* key, ke_variant* value)
    {
        try
        {
            var entry  = (TypeEntry)GCHandle.FromIntPtr((nint)ctx).Target!;
            var keyStr = Marshal.PtrToStringUTF8((nint)key);
            if (keyStr is null || value is null) return ke_result.KE_ERROR_INVALID_ARGUMENT;
            var managed = VariantToObject(*value);
            entry.SetProperty(entity, keyStr, managed);
            return ke_result.KE_OK;
        }
        catch (Exception ex)
        {
            PendingTrampolineException ??= ex;
            return ke_result.KE_ERROR;
        }
    }

    // Converts ke_variant to a generic managed object. No type knowledge — the receiver
    // (Framework's setProperty delegate) handles target-type conversion.
    private static object? VariantToObject(ke_variant v) => v.type switch
    {
        ke_variant_type.KE_VARIANT_NULL   => null,
        ke_variant_type.KE_VARIANT_BOOL   => v.b,
        ke_variant_type.KE_VARIANT_INT    => v.i,
        ke_variant_type.KE_VARIANT_FLOAT  => v.f,
        ke_variant_type.KE_VARIANT_STRING => Marshal.PtrToStringUTF8((nint)v.s),
        ke_variant_type.KE_VARIANT_VEC2   => v.v2,
        ke_variant_type.KE_VARIANT_VEC3   => v.v3,
        ke_variant_type.KE_VARIANT_VEC4   => v.v4,
        ke_variant_type.KE_VARIANT_QUAT   => v.q,
        ke_variant_type.KE_VARIANT_TABLE  => TableToDictionary(v.t),
        _                                 => null,
    };

    // Snapshots an inline ke_variant_table into a managed Dictionary<string, object?>.
    // The Framework-side property binder (NodeTypeRegistrar) detects this shape and
    // builds inline materials / shape descriptors / etc. without re-parsing TOML.
    private static Dictionary<string, object?> TableToDictionary(ke_variant_table* tbl)
    {
        var dict = new Dictionary<string, object?>((int)tbl->count);
        for (uint i = 0; i < tbl->count; i++)
        {
            var entry = tbl->entries[i];
            var key = Marshal.PtrToStringUTF8((nint)entry.key) ?? string.Empty;
            dict[key] = VariantToObject(entry.value);
        }
        return dict;
    }

    // ── Dispose ───────────────────────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_native != null) { _native->destroy(_native); _native = null; }
        foreach (var h in _handles) h.Free();
        _handles.Clear();
        foreach (var p in _nameStrings) Marshal.FreeCoTaskMem(p);
        _nameStrings.Clear();
    }
}
