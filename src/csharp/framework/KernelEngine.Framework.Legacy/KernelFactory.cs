namespace KernelEngine.Kernel;

/// <summary>
/// Default <see cref="IKernelFactory"/>: constructs concrete <c>KernelEngine.Kernel</c> primitives
/// and bridges to the thread-name TLS helpers from the C kernel.
/// Registered as a singleton by <see cref="ServiceCollectionExtensions.AddKernel"/>.
/// </summary>
public sealed class KernelFactory : IKernelFactory
{
    /// <inheritdoc/>
    public IFrameSync CreateFrameSync(int bufferCount) =>
        FrameSync.Create((uint)bufferCount);

    /// <inheritdoc/>
    public void SetCurrentThreadName(string name) => KernelThread.SetCurrentName(name);

    /// <inheritdoc/>
    public void AssertCurrentThread(string expected) => KernelThread.AssertCurrent(expected);
}
