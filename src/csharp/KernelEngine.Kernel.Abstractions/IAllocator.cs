namespace KernelEngine.Kernel;

/// <summary>
/// Marker interface for native memory allocators. Framework/user code passes <c>IAllocator</c>
/// instances around via DI; allocation primitives themselves are not exposed at this layer
/// (only the concrete Kernel implementations expose <c>Allocate</c>/<c>Free</c>).
/// </summary>
public interface IAllocator : IDisposable
{
    /// <summary>Resets the allocator state without freeing its backing memory. No-op when not supported.</summary>
    void Reset();
}

/// <summary>System-heap (malloc/free) allocator. Marker for DI.</summary>
public interface IMallocAllocator : IAllocator { }

/// <summary>Fixed-capacity bump allocator. Marker for DI.</summary>
public interface IArenaAllocator : IAllocator { }

/// <summary>Wraps another allocator to track statistics and detect leaks.</summary>
public interface IProxyAllocator : IAllocator
{
    /// <summary>Logs a memory usage report to the provided logger.</summary>
    void Report(ILogger? logger);
}
