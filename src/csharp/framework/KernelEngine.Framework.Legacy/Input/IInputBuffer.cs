using KernelEngine.Input;


namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Lock-free single-slot exchange of input snapshots between <c>ke.main</c> (producer)
/// and <c>ke.sim</c> (consumer). The latest snapshot replaces the previous one; missed
/// frames are intentional — sim sees the freshest input on its tick boundary.
/// </summary>
public interface IInputBuffer
{
    /// <summary>Publishes a new snapshot from ke.main. Overwrites the slot.</summary>
    void Produce(IInputReader snapshot);

    /// <summary>Reads the latest snapshot from ke.sim. Never null; returns an empty reader
    /// until the first <see cref="Produce"/> call.</summary>
    IInputReader Consume();
}
