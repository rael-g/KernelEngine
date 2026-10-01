namespace KernelEngine.Framework;

/// <summary>
/// Receives the signal payload types a node type takes part in.
/// </summary>
public interface ISignalDeclarer
{
    /// <summary>Declares <typeparamref name="T"/>'s signal, so a scene may name it.</summary>
    void Declare<T>() where T : unmanaged;
}
