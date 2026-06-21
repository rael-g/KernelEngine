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
    public NodeWorld NodeWorld { get; }

    private readonly IInputReader? _input;
    private readonly IInputReader? _prevInput;

    /// <summary>
    /// True if the given key was held down when input was last sampled.
    /// Returns false when no input service is registered.
    /// Key codes follow the GLFW convention (e.g. 87='W', 262=Right Arrow).
    /// </summary>
    public bool IsKeyDown(int key) => _input?.IsKeyDown(key) ?? false;

    /// <summary>
    /// True if the given key transitioned from up to down this tick (rising edge).
    /// Returns false when no input service is registered.
    /// </summary>
    public bool IsKeyJustPressed(int key)
        => (_input?.IsKeyDown(key) ?? false) && !(_prevInput?.IsKeyDown(key) ?? false);

    internal View(NodeWorld nodeWorld, float deltaTime, IInputReader? input, IInputReader? prevInput = null)
    {
        NodeWorld  = nodeWorld;
        DeltaTime  = deltaTime;
        _input     = input;
        _prevInput = prevInput;
    }
}
