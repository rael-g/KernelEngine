using System.Runtime.InteropServices;

namespace KernelEngine.Kernel;

/// <summary>
/// Base class for unmanaged memory allocators. All allocation is performed via
/// <c>NativeMemory</c>; no native vtable or C interop required.
/// </summary>
public abstract unsafe class Allocator : IAllocator
{
    private bool _disposed;

    public abstract void* Allocate(nuint size, nuint alignment = 16);
    public abstract void  Free(void* ptr);
    public abstract void* Reallocate(void* ptr, nuint newSize);
    public virtual  void  Reset() { }

    public void Dispose()
    {
        if (!_disposed)
        {
            _disposed = true;
            DisposeCore();
        }
    }

    protected virtual void DisposeCore() { }
}

/// <summary>
/// General-purpose allocator backed by the system heap (malloc/free).
/// </summary>
public sealed unsafe class MallocAllocator : Allocator, IMallocAllocator
{
    public override void* Allocate(nuint size, nuint alignment = 16) =>
        NativeMemory.AlignedAlloc(size, alignment);

    public override void Free(void* ptr) =>
        NativeMemory.AlignedFree(ptr);

    public override void* Reallocate(void* ptr, nuint newSize)
    {
        // NativeMemory doesn't have AlignedRealloc; alloc+copy+free
        if (ptr == null) return Allocate(newSize);
        void* newPtr = NativeMemory.AlignedAlloc(newSize, 16);
        if (newPtr == null) return null;
        NativeMemory.Copy(ptr, newPtr, newSize);
        NativeMemory.AlignedFree(ptr);
        return newPtr;
    }
}

/// <summary>
/// Fixed-capacity bump allocator. Very fast; reset all at once with <see cref="Allocator.Reset"/>.
/// </summary>
public sealed unsafe class ArenaAllocator : Allocator, IArenaAllocator
{
    private readonly void* _buffer;
    private readonly nuint _capacity;
    private nuint _offset;

    public ArenaAllocator(nuint capacity)
    {
        _capacity = capacity;
        _buffer   = NativeMemory.AlignedAlloc(capacity, 16);
        _offset   = 0;
    }

    public override void* Allocate(nuint size, nuint alignment = 16)
    {
        nuint aligned = (_offset + alignment - 1) & ~(alignment - 1);
        if (aligned + size > _capacity) return null;
        void* ptr = (byte*)_buffer + aligned;
        _offset = aligned + size;
        return ptr;
    }

    public override void  Free(void* ptr) { /* bump allocator; freed only on Reset/Dispose */ }
    public override void* Reallocate(void* ptr, nuint newSize) => Allocate(newSize);

    public override void Reset() => _offset = 0;

    protected override void DisposeCore() => NativeMemory.AlignedFree(_buffer);
}

/// <summary>
/// Wraps another allocator to track statistics and detect leaks.
/// </summary>
public sealed unsafe class ProxyAllocator : Allocator, IProxyAllocator
{
    private readonly Allocator             _inner;
    private readonly string               _name;
    private readonly Dictionary<nint, nuint> _sizes = new();
    private ulong _totalAllocated;
    private ulong _totalFreed;
    private ulong _activeBytes;
    private uint  _activeAllocs;

    public ProxyAllocator(Allocator inner, string name)
    {
        _inner = inner;
        _name  = name;
    }

    public override void* Allocate(nuint size, nuint alignment = 16)
    {
        void* ptr = _inner.Allocate(size, alignment);
        if (ptr != null)
        {
            _sizes[(nint)ptr] = size;
            _totalAllocated  += size;
            _activeBytes     += size;
            _activeAllocs++;
        }
        return ptr;
    }

    public override void Free(void* ptr)
    {
        if (ptr == null) return;
        if (_sizes.Remove((nint)ptr, out nuint size))
        {
            _totalFreed  += size;
            _activeBytes -= size;
            if (_activeAllocs > 0) _activeAllocs--;
        }
        _inner.Free(ptr);
    }

    public override void* Reallocate(void* ptr, nuint newSize) => _inner.Reallocate(ptr, newSize);

    /// <inheritdoc/>
    public void Report(ILogger? logger)
    {
        string msg = $"[ProxyAllocator '{_name}'] active={_activeAllocs} allocs, " +
                     $"total_allocated={_totalAllocated}, total_freed={_totalFreed}";
        logger?.Log(LogLevel.Info, "ProxyAllocator", msg);
    }

    /// <inheritdoc/>
    public AllocatorStats GetStats() =>
        new(_totalAllocated, _totalFreed, _activeBytes, _activeAllocs);

    protected override void DisposeCore() => _inner.Dispose();
}
