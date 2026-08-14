using KernelEngine.Input;


namespace KernelEngine.Framework;

/// <summary>
/// The funnel through which a <see cref="Node"/>'s per-frame logic observes
/// and mutates the world. Passed by ref to <see cref="Node.OnUpdate"/>.
/// </summary>
/// <remarks>
/// A <c>ref struct</c> by design: it cannot be boxed, captured in a closure,
/// stored in a field, or escape the stack frame of the method that received it.
/// This is the structural guarantee that script-side code cannot smuggle world
/// access past the engine's safety rules.
/// </remarks>
public readonly ref struct View
{
    /// <summary>Time since the previous tick, in seconds.</summary>
    public float DeltaTime { get; }

    /// <summary>The node world this node belongs to.</summary>
    /// <summary>
    /// The world driving this tick. Internal for the same reason
    /// <see cref="Node"/> keeps its own private: a behavior reaching the whole
    /// world through its view is the same unrestricted access by another door.
    /// </summary>
    internal NodeWorld NodeWorld { get; }

    private readonly IInputReader? _input;

    /// <summary>
    /// The native system context for this tick. Opaque handle forwarded to
    /// structural operations (node create/destroy) so they defer safely to the
    /// wave barrier. Zero outside a running system.
    /// </summary>
    internal nint SystemContext { get; }

    /// <summary>
    /// True if the given key was held down when input was last sampled.
    /// Returns false when no input service is registered.
    /// Key codes follow the GLFW convention (e.g. 87='W', 262=Right Arrow).
    /// </summary>
    public bool IsKeyDown(int key) => _input?.IsKeyDown((Key)key) ?? false;

    /// <summary>
    /// True if the given key transitioned from up to down this tick (rising edge).
    /// Returns false when no input service is registered.
    /// </summary>
    public bool IsKeyJustPressed(int key) => _input?.IsKeyPressed((Key)key) ?? false;

    internal View(NodeWorld nodeWorld, float deltaTime, IInputReader? input, nint systemCtx = default)
    {
        NodeWorld     = nodeWorld;
        DeltaTime     = deltaTime;
        _input        = input;
        SystemContext = systemCtx;
    }
}
