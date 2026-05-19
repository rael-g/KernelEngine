namespace KernelEngine.Kernel;

/// <summary>
/// Factory + ambient services for engine primitives that consumers (Framework, game code)
/// would otherwise have to construct via concrete <c>KernelEngine.Kernel</c> types.
/// Registered as a singleton by <c>AddKernel()</c>; resolved via DI.
/// </summary>
/// <remarks>
/// This interface exists so the <see cref="KernelEngine.Framework"/> assembly can be physically
/// decoupled from the <c>KernelEngine.Kernel</c> implementation assembly. Plugins still
/// reference Kernel directly to wire their backends; only the Framework / user code path
/// goes through these abstractions.
/// </remarks>
public interface IEngineHost
{
    // ── Allocator helpers ──────────────────────────────────────────────────

    /// <summary>Wraps <paramref name="inner"/> in a proxy allocator that tracks stats / leaks.</summary>
    IProxyAllocator CreateProxyAllocator(IAllocator inner, string name);

    // ── World + frame primitives ───────────────────────────────────────────

    IWorld CreateWorld(IAllocator allocator);
    IFrameSync CreateFrameSync(IAllocator allocator, int bufferCount);

    // ── Threading ──────────────────────────────────────────────────────────

    /// <summary>Publishes <paramref name="name"/> as the current thread's name (TLS + OS via IDevPlatform).</summary>
    void SetCurrentThreadName(string name);

    /// <summary>Asserts the calling thread's name matches <paramref name="expected"/> in debug builds; no-op in release.</summary>
    void AssertCurrentThread(string expected);

    /// <summary>Creates a managed thread that runs <paramref name="action"/>. Disposing joins.</summary>
    IKernelThread CreateThread(IAllocator allocator, string name, IDevPlatform? devPlatform, Action action);

    /// <summary>Sets a per-frame input snapshot reader visible to <c>ke.sim</c> systems via TLS.</summary>
    void SetCurrentInputReader(IInputReader? reader);
}
