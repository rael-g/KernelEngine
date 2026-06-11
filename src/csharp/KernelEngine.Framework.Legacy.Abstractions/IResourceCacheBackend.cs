namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Backend contract for the GPU resource cache (refcount + path-keyed dedup) provided by the
/// native plugin. Sugar layer (<c>Resource</c>, <c>ResourceManager</c>, <c>Assets</c>) consumes
/// this interface; the unsafe wrapper lives in <c>KernelEngine.Framework.Legacy.Native</c>.
/// </summary>
public interface IResourceCacheBackend : IDisposable
{
    /// <summary>
    /// Registers <paramref name="handle"/> with refcount = 1. <paramref name="onDestroy"/> is
    /// fired (on the renderer thread) when the count drops to zero.
    /// </summary>
    void RegisterResource(uint handle, Action onDestroy);

    /// <summary>
    /// Registers a handleless composite resource (e.g. a Model bundle). Returns the synthetic
    /// handle to use for subsequent retain/release.
    /// </summary>
    uint RegisterComposite(Action onDestroy);

    void Retain(uint handle);
    void Release(uint handle);

    /// <summary>
    /// Path cache lookup. On hit, the backend retains the handle on the caller's behalf and
    /// returns it via <paramref name="handle"/>.
    /// </summary>
    bool TryGetCached(string key, out uint handle);

    void CacheInsert(string key, uint handle);
}
