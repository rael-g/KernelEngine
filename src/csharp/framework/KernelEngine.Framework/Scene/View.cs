using KernelEngine.Input;


namespace KernelEngine.Framework;

/// <summary>
/// The funnel through which a <see cref="Node"/>'s per-frame logic observes
/// and mutates the world. Passed by ref to <see cref="Node.OnUpdate"/>.
/// </summary>
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
    internal ScriptHost ScriptHost { get; }

    private readonly IInputReader? _input;

    /// <summary>
    /// The queue this tick's structural changes are recorded into, applied at the
    /// wave barrier.
    /// </summary>
    /// <exception cref="InvalidOperationException">The view was not made inside a running system.</exception>
    internal KernelEngine.Ecs.EcsCommands Commands =>
        _commands ?? throw new InvalidOperationException("This view does not belong to a running system.");

    private readonly KernelEngine.Ecs.EcsCommands? _commands;

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

    internal View(ScriptHost scriptHost, float deltaTime, IInputReader? input, nint systemCtx = default)
    {
        ScriptHost     = scriptHost;
        DeltaTime     = deltaTime;
        _input        = input;
        _commands     = systemCtx == 0 ? null : KernelEngine.Runtime.SystemCtx.Of(systemCtx).Commands;
    }
}
