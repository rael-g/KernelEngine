namespace KernelEngine.Kernel;

/// <summary>
/// Default <see cref="IEngineHost"/> implementation: thin facade over the concrete
/// <c>KernelEngine.Kernel</c> primitives (<see cref="Allocator"/>, <see cref="World"/>,
/// <see cref="FrameSync"/>, <see cref="KernelThread"/>, <see cref="Input"/>).
/// Registered as a singleton by <see cref="ServiceCollectionExtensions.AddKernel"/>.
/// </summary>
public sealed class EngineHost : IEngineHost
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
    public void SetCurrentThreadName(string name) => KernelThread.SetCurrentName(name);

    /// <inheritdoc/>
    public void AssertCurrentThread(string expected) => KernelThread.AssertCurrent(expected);

    /// <inheritdoc/>
    public IKernelThread CreateThread(IAllocator allocator, string name, IDevPlatform? devPlatform, Action action) =>
        KernelThread.Create((Allocator)allocator, name, action, (DevPlatform?)devPlatform);

    /// <inheritdoc/>
    public void SetCurrentInputReader(IInputReader? reader) => Input.SetCurrentReader(reader);

    /// <inheritdoc/>
    public IInputBuffer CreateInputBuffer() => new InputBuffer();

    /// <inheritdoc/>
    public IResourceCommandQueue CreateResourceCommandQueue() => new ResourceCommandQueue();

    /// <inheritdoc/>
    public ISceneWriter CreateSceneWriter(IFramePacket packet) => new FramePacketSceneWriter((FramePacket)packet);
}
