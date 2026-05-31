using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Tier S round-trip implementation of <c>ke_resource_cache</c>.
/// <para>
/// Wraps the existing <see cref="Resource"/> ref-counting and <see cref="Assets"/> path-cache
/// behind the C ABI vtable. Non-.NET bindings (Lua, C++) can call <c>retain</c>/<c>release</c>
/// on GPU resource handles without reimplementing lifetime management.
/// Once a native C++ plugin provides its own <c>ke_resource_cache</c>, this bridge is discarded.
/// </para>
/// </summary>
internal sealed unsafe class CSharpResourceCache : IDisposable
{
    // ── Static registry: uint handle → Resource ───────────────────────────────
    // Static so trampolines (which are static methods) can reach it.
    private static readonly Dictionary<uint, Resource> s_resources = [];
    private static readonly Dictionary<string, uint>   s_pathCache = new(StringComparer.Ordinal);
    private static readonly object s_gate = new();

    private ke_resource_cache* _native;
    private GCHandle _selfHandle;
    private bool _disposed;

    public CSharpResourceCache()
    {
        _selfHandle = GCHandle.Alloc(this);
        _native = (ke_resource_cache*)NativeMemory.Alloc((nuint)sizeof(ke_resource_cache));
        *_native = new ke_resource_cache
        {
            handle            = (void*)GCHandle.ToIntPtr(_selfHandle),
            register_resource = &NativeRegister,
            retain            = &NativeRetain,
            release           = &NativeRelease,
            try_get_cached    = &NativeTryGetCached,
            cache_insert      = &NativeCacheInsert,
            cache_evict       = &NativeCacheEvict,
            destroy           = &NativeDestroy,
        };
    }

    public ke_resource_cache* Native => _native;

    // ── Managed registration (called by ResourceManager after GPU creation) ───

    /// <summary>
    /// Registers a newly-created resource in the cache (refcount starts at 1).
    /// Call once per resource immediately after <see cref="ResourceManager"/> creates it.
    /// </summary>
    public void Register(uint handle, Resource resource)
    {
        lock (s_gate)
            s_resources[handle] = resource;

        // When the managed resource is destroyed (refcount → 0), remove from our map.
        resource.OnDestroyed += () =>
        {
            lock (s_gate)
                s_resources.Remove(handle);
        };
    }

    /// <summary>Registers a path → handle mapping for later dedup lookups.</summary>
    public void InsertPath(string path, uint handle)
    {
        lock (s_gate)
            s_pathCache[path] = handle;
    }

    /// <summary>Tries to get a cached handle by path and retains it on behalf of the caller.</summary>
    public bool TryGetCached(string path, out uint handle)
    {
        lock (s_gate)
        {
            if (s_pathCache.TryGetValue(path, out handle) && s_resources.ContainsKey(handle))
            {
                s_resources[handle].Retain();
                return true;
            }
        }
        handle = uint.MaxValue;
        return false;
    }

    // ── Trampolines ───────────────────────────────────────────────────────────

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeRegister(
        ke_resource_cache* self, uint handle,
        delegate* unmanaged[Cdecl]<uint, void*, void> destroyFn, void* destroyCtx)
    {
        if (handle == uint.MaxValue) return ke_result.KE_ERROR_INVALID_ARGUMENT;
        // In the round-trip, resources are registered via the managed Register() method.
        // The native register slot exists for future C++ plugins that create resources directly.
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeRetain(ke_resource_cache* self, uint handle)
    {
        lock (s_gate)
        {
            if (!s_resources.TryGetValue(handle, out var res)) return ke_result.KE_ERROR_NOT_FOUND;
            res.Retain();
            return ke_result.KE_OK;
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static ke_result NativeRelease(ke_resource_cache* self, uint handle)
    {
        Resource? res;
        lock (s_gate)
        {
            if (!s_resources.TryGetValue(handle, out res)) return ke_result.KE_ERROR_NOT_FOUND;
        }
        res.Release(); // Release outside the lock (may call DestroyNative → ke.render queue)
        return ke_result.KE_OK;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static bool NativeTryGetCached(ke_resource_cache* self, sbyte* key, uint* outHandle)
    {
        var path = Marshal.PtrToStringUTF8((nint)key);
        if (path == null) { if (outHandle != null) *outHandle = uint.MaxValue; return false; }

        lock (s_gate)
        {
            if (s_pathCache.TryGetValue(path, out var h) && s_resources.ContainsKey(h))
            {
                s_resources[h].Retain();
                if (outHandle != null) *outHandle = h;
                return true;
            }
        }
        if (outHandle != null) *outHandle = uint.MaxValue;
        return false;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCacheInsert(ke_resource_cache* self, sbyte* key, uint handle)
    {
        var path = Marshal.PtrToStringUTF8((nint)key);
        if (path == null) return;
        lock (s_gate)
            s_pathCache[path] = handle;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeCacheEvict(ke_resource_cache* self, sbyte* key)
    {
        var path = Marshal.PtrToStringUTF8((nint)key);
        if (path == null) return;
        lock (s_gate)
            s_pathCache.Remove(path);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void NativeDestroy(ke_resource_cache* self) { /* managed via IDisposable */ }

    // ── IDisposable ───────────────────────────────────────────────────────────

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        if (_native != null) { NativeMemory.Free(_native); _native = null; }
        if (_selfHandle.IsAllocated) _selfHandle.Free();
    }
}
