namespace KernelEngine.Kernel;

/// <summary>
/// Default <see cref="IKernelFactory"/>: constructs concrete <c>KernelEngine.Kernel</c> primitives
/// (<see cref="ProxyAllocator"/>, <see cref="World"/>, <see cref="FrameSync"/>, <see cref="KernelThread"/>)
/// and exposes thread-name affinity helpers. Registered as a singleton by
/// <see cref="ServiceCollectionExtensions.AddKernel"/>.
/// </summary>
public sealed class KernelFactory : IKernelFactory
{
    /// <inheritdoc/>
    public IProxyAllocator CreateProxyAllocator(IAllocator inner, string name) =>
        new ProxyAllocator((Allocator)inner, name);

    /// <inheritdoc/>
    public IWorld CreateWorld(IAllocator allocator) =>
        new World((Allocator)allocator);

    /// <inheritdoc/>
    public IFrameSync CreateFrameSync(IAllocator allocator, int bufferCount) =>
        FrameSync.Create((Allocator)allocator, (uint)bufferCount);

    /// <inheritdoc/>
    public IKernelThread CreateThread(IAllocator allocator, string name, IDevPlatform? devPlatform, Action action) =>
        KernelThread.Create((Allocator)allocator, name, action, (DevPlatform?)devPlatform);

    /// <inheritdoc/>
    public void SetCurrentThreadName(string name) => KernelThread.SetCurrentName(name);

    /// <inheritdoc/>
    public void AssertCurrentThread(string expected) => KernelThread.AssertCurrent(expected);
}
