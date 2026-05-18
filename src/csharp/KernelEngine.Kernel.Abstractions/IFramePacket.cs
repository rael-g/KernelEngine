using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>
/// Snapshot of one rendered frame, written by simulation systems and consumed by the renderer.
/// All methods are safe (no <c>unsafe</c> on caller side); implementations marshal to the native
/// <c>ke_frame_packet</c> internally.
/// </summary>
/// <remarks>
/// This interface is the canonical surface render systems write through when populating a frame.
/// Caso 3 of B5.1 fills out the per-frame write methods (SetCamera, AddPointLight, RecordDraw,
/// etc.); for now it only carries the read/release hooks needed by <see cref="IFrameSync"/>.
/// </remarks>
public interface IFramePacket
{
    /// <summary>Releases this packet back to the writer pool. Called by the render thread.</summary>
    void EndRead();

    /// <summary>Releases this packet to the reader (sim thread → render thread). Called by sim.</summary>
    void EndWrite();
}
