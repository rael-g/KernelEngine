namespace KernelEngine.Kernel;

/// <summary>
/// Factory for kernel primitives that require access to the <c>KernelEngine.Kernel</c> implementation assembly.
/// Registered as a singleton by <c>AddKernel()</c>; injected via DI.
/// </summary>
public interface IKernelFactory
{
    /// <summary>Creates a frame-sync ring with <paramref name="bufferCount"/> slots (caller's policy).</summary>
    IFrameSync CreateFrameSync(int bufferCount);

    /// <summary>
    /// Publishes <paramref name="name"/> as the calling thread's name. Sets the cross-language
    /// kernel TLS slot used by <c>ke_thread_assert_current</c>.
    /// </summary>
    void SetCurrentThreadName(string name);

    /// <summary>Asserts the calling thread's name matches <paramref name="expected"/> (debug only; no-op in release).</summary>
    void AssertCurrentThread(string expected);
}
