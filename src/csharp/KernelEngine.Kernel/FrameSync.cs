using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Managed wrapper for <c>ke_frame_sync</c>.
/// Coordinates double/triple-buffered frame data handoff between the sim thread (writer)
/// and the render thread (reader).
/// </summary>
public sealed unsafe class FrameSync : IFrameSync
{
    private ke_frame_sync* _native;
    private Allocator      _alloc;

    private FrameSync(ke_frame_sync* native, Allocator alloc)
    {
        _native = native;
        _alloc  = alloc;
    }

    /// <summary>
    /// Creates a frame sync with the given ring buffer size and pre-allocated array capacities.
    /// </summary>
    /// <param name="alloc">Engine allocator for all internal memory.</param>
    /// <param name="bufferCount">Ring buffer depth (2 = double-buffer, 3 = triple-buffer).</param>
    /// <param name="drawCapacity">Max draw commands per frame.</param>
    /// <param name="pointLightCapacity">Max point lights per frame.</param>
    /// <param name="spotLightCapacity">Max spot lights per frame.</param>
    public static FrameSync Create(Allocator alloc,
                                   uint      bufferCount       = 2,
                                   uint      drawCapacity      = 2048,
                                   uint      pointLightCapacity = 512,
                                   uint      spotLightCapacity  = 512)
    {
        ke_frame_sync* native;
        KernelException.ThrowIfFailed(NativeMethods.frame_sync_std_create(
                alloc.Native, bufferCount,
                drawCapacity, pointLightCapacity, spotLightCapacity,
                &native).ToManaged());
        return new FrameSync(native, alloc);
    }

    /// <summary>
    /// Acquires a writable <see cref="FramePacket"/> (sim thread).
    /// Blocks if all buffers are currently being read by the render thread.
    /// </summary>
    public FramePacket BeginWrite()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        var ptr = _native->begin_write(_native);
        return new FramePacket(ptr, _native, isWriter: true);
    }

    /// <summary>
    /// Acquires the next readable <see cref="FramePacket"/> (render thread).
    /// Blocks until the sim thread signals a frame is ready.
    /// </summary>
    public FramePacket BeginRead()
    {
        ObjectDisposedException.ThrowIf(_native == null, this);
        var ptr = _native->begin_read(_native);
        return new FramePacket(ptr, _native, isWriter: false);
    }

    IFramePacket IFrameSync.BeginWrite() => BeginWrite();
    IFramePacket IFrameSync.BeginRead() => BeginRead();

    /// <inheritdoc/>
    public void Dispose()
    {
        if (_native != null)
        {
            _native->destroy(_native, _alloc.Native);
            _native = null;
        }
    }
}
