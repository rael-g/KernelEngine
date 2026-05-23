namespace KernelEngine.Framework;

/// <summary>
/// Base for ref-counted GPU resources (<see cref="Material"/>, <see cref="Mesh"/>, <see cref="Texture"/>).
/// A resource starts with a reference count of 1 (the creator's). Sharing it (e.g. caching, or the
/// same material on many meshes) <see cref="Retain"/>s; dropping a reference <see cref="Release"/>s.
/// When the count reaches zero the underlying GPU handle is destroyed via the resource factory
/// (which routes the destroy to ke.render). Resource methods are expected to be called from ke.sim.
/// </summary>
public abstract class Resource : IDisposable
{
    private int _refCount = 1;
    private bool _destroyed;

    /// <summary>Current reference count (for diagnostics/tests).</summary>
    public int ReferenceCount => Volatile.Read(ref _refCount);

    /// <summary>Increments the reference count; returns this for fluent use. Pair every call with a <see cref="Release"/>.</summary>
    public Resource Retain()
    {
        ObjectDisposedException.ThrowIf(_destroyed, this);
        Interlocked.Increment(ref _refCount);
        return this;
    }

    /// <summary>
    /// Optional hook fired once, after <see cref="DestroyNative"/>, when the reference count
    /// reaches zero. Used by <see cref="Assets"/> to evict the resource from its cache without
    /// coupling <see cref="Resource"/> to the cache. Set once by the creator.
    /// </summary>
    internal Action? OnDestroyed { get; set; }

    /// <summary>Decrements the reference count; destroys the GPU handle when it reaches zero.</summary>
    public void Release()
    {
        int remaining = Interlocked.Decrement(ref _refCount);
        if (remaining > 0) return;
        if (remaining < 0)
            throw new InvalidOperationException($"{GetType().Name} released more times than retained.");
        _destroyed = true;
        DestroyNative();
        OnDestroyed?.Invoke();
    }

    /// <summary><see cref="Release"/>s one reference (so <c>using</c> / DI disposal frees a resource).</summary>
    public void Dispose() => Release();

    /// <summary>Destroys the underlying GPU handle. Called once when the reference count hits zero.</summary>
    protected abstract void DestroyNative();
}
