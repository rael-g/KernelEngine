using KernelEngine.Input;


namespace KernelEngine.Framework;

/// <summary>
/// What a <see cref="Node"/>'s per-frame logic is given for one tick: the time step, the input
/// state and the command queue of the running system. Passed by reference to
/// <see cref="Node.OnUpdate"/> and valid only during that call.
/// </summary>
public readonly ref struct View
{
    /// <summary>Time since the previous tick, in seconds.</summary>
    public float DeltaTime { get; }

    /// <summary>The script host driving this tick.</summary>
    internal ScriptHost ScriptHost { get; }

    private readonly IInputReader? _input;

    /// <summary>
    /// The queue this tick's structural changes are recorded into, applied at the
    /// wave barrier.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// The view was not made inside a running system.
    /// </exception>
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
        ScriptHost = scriptHost;
        DeltaTime = deltaTime;
        _input = input;
        _commands = systemCtx == 0 ? null : KernelEngine.Runtime.SystemCtx.Of(systemCtx).Commands;
    }
}
