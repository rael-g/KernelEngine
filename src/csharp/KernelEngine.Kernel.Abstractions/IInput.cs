namespace KernelEngine.Kernel;

/// <summary>
/// The input service that processes OS messages on <c>ke.main</c> and produces frame snapshots
/// consumable by <c>ke.sim</c> via <see cref="IInputReader"/>.
/// </summary>
public interface IInput : IDisposable
{
    /// <summary>Processes pending messages and updates internal state. Must run on ke.main.</summary>
    Result Update();
}
