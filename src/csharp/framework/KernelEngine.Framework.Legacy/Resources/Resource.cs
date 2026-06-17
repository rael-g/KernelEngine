namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Base for ref-counted GPU resources (<see cref="Material"/>, <see cref="Mesh"/>, <see cref="Texture"/>).
/// Refcount and path-keyed dedup live entirely in the native <c>ke_resource_cache</c> — this class
/// is a thin C# wrapper that relays <see cref="Retain"/> and <see cref="Release"/> across the ABI.
/// </summary>
public abstract class Resource : IDisposable
{
    internal uint RawHandle { get; }
    private readonly IResourceCacheBackend _cache;

    private protected Resource(IResourceCacheBackend cache, uint handle)
    {
        _cache    = cache;
        RawHandle = handle;
    }

    /// <summary>Increments the reference count; returns this for fluent use.</summary>
    public Resource Retain()
    {
        _cache.Retain(RawHandle);
        return this;
    }

    /// <summary>Decrements the reference count; destroys the GPU handle when it reaches zero.</summary>
    public void Release() => _cache.Release(RawHandle);

    /// <summary><see cref="Release"/>s one reference (so <c>using</c> / DI disposal frees a resource).</summary>
    public void Dispose() => Release();
}
