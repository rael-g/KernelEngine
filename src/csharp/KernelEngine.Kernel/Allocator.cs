using System.Runtime.InteropServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Base class for native memory allocators.
/// </summary>
public abstract unsafe class Allocator : IAllocator
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

    public void* Allocate(nuint size, nuint alignment = 0)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->alloc(_native, size, alignment);
    }

    public void Free(void* ptr)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        _native->free(_native, ptr);
    }

    public void* Reallocate(void* ptr, nuint newSize)
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        return _native->realloc(_native, ptr, newSize);
    }

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
public sealed unsafe class MallocAllocator : Allocator, IMallocAllocator
{
    public MallocAllocator() : base(NativeMethods.allocator_malloc_create()) { }
}

/// <summary>
/// Fixed-capacity bump allocator. Very fast; reset all at once with <see cref="Allocator.Reset"/>.
/// </summary>
public sealed unsafe class ArenaAllocator : Allocator, IArenaAllocator
{
    public ArenaAllocator(nuint capacity) : base(NativeMethods.allocator_arena_create(capacity)) { }
}

/// <summary>
/// Wraps another allocator to track statistics and detect leaks.
/// </summary>
public sealed unsafe class ProxyAllocator : Allocator, IProxyAllocator
{
    public ProxyAllocator(Allocator inner, string name)
        : base(CreateProxy(inner, name)) { }

    private static ke_allocator* CreateProxy(Allocator inner, string name)
    {
        var namePtr = Marshal.StringToHGlobalAnsi(name);
        try
        {
            return NativeMethods.allocator_proxy_create(inner.Native, (sbyte*)namePtr);
        }
        finally
        {
            Marshal.FreeHGlobal(namePtr);
        }
    }

    /// <inheritdoc/>
    public void Report(ILogger? logger)
    {
        ke_logger* nativeLogger = null;
        try { if (logger is Logger l) nativeLogger = l.Native; }
        catch (ObjectDisposedException) { }

        NativeMethods.allocator_proxy_report(Native, nativeLogger);
    }
}
