namespace KernelEngine.Kernel;

/// <summary>
/// Double-buffered handoff between the simulation thread (writer) and the render thread (reader).
/// Implementations wrap the native ring buffer.
/// </summary>
public interface IFrameSync : IDisposable
{
    /// <summary>Acquires a frame packet for writing; blocks if no slot is available.</summary>
    IFramePacket BeginWrite();

    /// <summary>Acquires a frame packet for reading; blocks if no packet is ready.</summary>
    IFramePacket BeginRead();
}
