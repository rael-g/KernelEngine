using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Base class for native memory allocators.
/// </summary>
public abstract unsafe class Allocator : IDisposable
{
    private ke_allocator* _native;

    public ke_allocator* Native
    {
        get
        {
            ObjectDisposedException.ThrowIf(_native == null, this);
            return _native;
        }
    }

    private protected Allocator(ke_allocator* native) => _native = native;

    /// <summary>Resets the allocator state without freeing its backing memory.</summary>
    public void Reset()
    {
        if (_native->reset != null)
            _native->reset(_native);
    }

    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native);
            _native = null;
        }
    }
}

/// <summary>
/// General-purpose allocator backed by the system heap (malloc/free).
/// </summary>
public sealed unsafe class MallocAllocator : Allocator
{
    public MallocAllocator() : base(NativeMethods.allocator_malloc_create()) { }
}

/// <summary>
/// Fixed-capacity bump allocator. Very fast; reset all at once with <see cref="Allocator.Reset"/>.
/// </summary>
public sealed unsafe class ArenaAllocator : Allocator
{
    public ArenaAllocator(nuint capacity) : base(NativeMethods.allocator_arena_create(capacity)) { }
}
