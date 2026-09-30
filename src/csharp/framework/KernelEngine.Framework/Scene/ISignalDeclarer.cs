namespace KernelEngine.Framework;

/// <summary>
/// Receives the signal payload types a node type takes part in.
/// </summary>
/// <remarks>
/// The method is generic rather than taking a <see cref="System.Type"/> because the
/// payload's size is half of a signal's identity, and only a type parameter yields it
/// exactly — reading a size back off a runtime <see cref="System.Type"/> answers a
/// different question than <c>sizeof</c> does for a struct laid out for a C ABI.
/// </remarks>
public interface ISignalDeclarer
{
    /// <summary>Declares <typeparamref name="T"/>'s signal, so a scene may name it.</summary>
    void Declare<T>() where T : unmanaged;
}
