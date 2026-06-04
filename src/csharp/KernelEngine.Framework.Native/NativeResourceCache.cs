using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text;
using KernelEngine.Framework.Native;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Managed wrapper over the native <c>ke_resource_cache</c> primitive. Refcounts
/// and path-keyed dedup live entirely on the C side; this wrapper just relays calls
/// and dispatches the destroy callback back to a managed delegate.
/// </summary>
internal sealed unsafe class NativeResourceCache : IResourceCacheBackend
{
    private ke_resource_cache* _native;

    public NativeResourceCache(Allocator allocator)
    {
        ke_resource_cache* p;
        KernelException.ThrowIfFailed(
            KernelEngine.Framework.Native.NativeMethods.resource_cache_create(allocator.Native, &p).ToManaged());
        _native = p;
    }

    /// <summary>
    /// Registers <paramref name="handle"/> with refcount = 1. <paramref name="onDestroy"/>
    /// is fired (on the renderer thread) when the count drops to zero.
    /// </summary>
    public void RegisterResource(uint handle, Action onDestroy)
    {
        var gch = GCHandle.Alloc(onDestroy);
        KernelException.ThrowIfFailed(
            _native->register_resource(_native, handle, &OnDestroyTrampoline, (void*)GCHandle.ToIntPtr(gch)).ToManaged());
    }

    // Composite resources (e.g. Model) have no real GPU handle. We mint a synthetic
    // one in a high range that can't collide with renderer-issued small uint handles,
    // and avoid KE_RESOURCE_HANDLE_NONE (UINT32_MAX).
    private static int s_compositeCounter = unchecked((int)0x80000000);

    /// <summary>
    /// Registers a composite (handleless) resource. Returns the synthetic handle to use
    /// for subsequent Retain/Release/Dispose.
    /// </summary>
    public uint RegisterComposite(Action onDestroy)
    {
        uint h = unchecked((uint)Interlocked.Increment(ref s_compositeCounter));
        if (h == uint.MaxValue) h = unchecked((uint)Interlocked.Increment(ref s_compositeCounter));
        RegisterResource(h, onDestroy);
        return h;
    }

    public void Retain(uint handle) =>
        KernelException.ThrowIfFailed(_native->retain(_native, handle).ToManaged());

    public void Release(uint handle) =>
        KernelException.ThrowIfFailed(_native->release(_native, handle).ToManaged());

    /// <summary>
    /// Looks up <paramref name="key"/> in the path cache. On hit, retains the handle
    /// on the caller's behalf and returns it via <paramref name="handle"/>.
    /// </summary>
    public bool TryGetCached(string key, out uint handle)
    {
        var bytes = Encoding.UTF8.GetBytes(key + "\0");
        uint h;
        bool found;
        fixed (byte* p = bytes)
        {
            found = _native->try_get_cached(_native, (sbyte*)p, &h) != 0;
        }
        handle = h;
        return found;
    }

    public void CacheInsert(string key, uint handle)
    {
        var bytes = Encoding.UTF8.GetBytes(key + "\0");
        fixed (byte* p = bytes)
        {
            _native->cache_insert(_native, (sbyte*)p, handle);
        }
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(CallConvCdecl) })]
    private static void OnDestroyTrampoline(uint handle, void* ctx)
    {
        var gch = GCHandle.FromIntPtr((IntPtr)ctx);
        try
        {
            var action = (Action?)gch.Target;
            action?.Invoke();
        }
        finally
        {
            gch.Free();
        }
    }

    public void Dispose()
    {
        if (_native is not null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}
