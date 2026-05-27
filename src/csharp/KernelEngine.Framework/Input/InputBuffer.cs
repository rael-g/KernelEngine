using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>Null-object input reader used as the empty sentinel before the first snapshot arrives.</summary>
internal sealed class EmptyInputReader : IInputReader
{
    public bool IsKeyDown(int keyCode) => false;
    public System.Numerics.Vector2 MousePosition => default;
    public System.Numerics.Vector2 MouseDelta => default;
    public System.Numerics.Vector2 ScrollDelta => default;
    public bool IsMouseButtonDown(int button) => false;
}

/// <summary>
/// Lock-free single-slot exchange of <see cref="IInputReader"/> between ke.main (producer)
/// and ke.sim (consumer). Part of the Framework's 3-thread policy.
/// </summary>
public sealed class InputBuffer : IInputBuffer
{
    private static readonly IInputReader Empty = new EmptyInputReader();
    private IInputReader _latest = Empty;

    public void Produce(IInputReader snapshot) => Volatile.Write(ref _latest, snapshot);
    public IInputReader Consume() => Volatile.Read(ref _latest);
}
