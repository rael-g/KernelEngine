namespace KernelEngine.Kernel;

/// <summary>
/// Factory for the concrete kernel primitives that a consumer cannot construct directly
/// because they live in the <c>KernelEngine.Kernel</c> implementation assembly. Mirrors the
/// C kernel's create functions (<c>ke_world_create</c>, <c>ke_frame_sync_create</c>,
/// <c>ke_thread_create</c>, …). The caller supplies all parameters, so no policy lives in the kernel.
/// Registered as a singleton by <c>AddKernel()</c>; injected via DI.
/// </summary>
public interface IKernelFactory
{
    /// <summary>Wraps <paramref name="inner"/> in a proxy allocator that tracks stats / leaks.</summary>
    IProxyAllocator CreateProxyAllocator(IAllocator inner, string name);

    /// <summary>Creates a world owning an ECS registry and the system graph.</summary>
    IWorld CreateWorld(IAllocator allocator);

    /// <summary>Creates a frame-sync ring with <paramref name="bufferCount"/> slots (caller's policy).</summary>
    IFrameSync CreateFrameSync(IAllocator allocator, int bufferCount);

    /// <summary>Creates and starts a named kernel thread running <paramref name="action"/>. Disposing joins.</summary>
    IKernelThread CreateThread(IAllocator allocator, string name, IDevPlatform? devPlatform, Action action);

    /// <summary>Publishes <paramref name="name"/> as the calling thread's name (TLS + OS via DevPlatform).</summary>
    void SetCurrentThreadName(string name);

    /// <summary>Asserts the calling thread's name matches <paramref name="expected"/> (debug only; no-op in release).</summary>
    void AssertCurrentThread(string expected);
}
