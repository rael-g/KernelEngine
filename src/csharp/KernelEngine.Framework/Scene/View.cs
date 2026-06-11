using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// The funnel through which a <see cref="Node"/>'s per-frame logic observes
/// and mutates the world. Passed by ref to <see cref="Node.OnUpdate"/>.
/// </summary>
/// <remarks>
/// A <c>ref struct</c> by design: it cannot be boxed, captured in a closure,
/// stored in a field, or escape the stack frame of the method that received
/// it. This is the structural guarantee that script-side code cannot smuggle
/// world access past the engine's safety rules (see the script-safety doctrine
/// for the full set of bans the analyzer enforces on top — reflection, unsafe,
/// DllImport, dynamic).
/// <para>
/// First version exposes only what the migrated examples need; the surface
/// grows as scripts demand it (entity spawn/destroy, component access by
/// type, input, time singletons, etc.) — never via god-properties on Node.
/// </para>
/// </remarks>
public readonly ref struct View
{
    /// <summary>Time since the previous tick, in seconds.</summary>
    public float DeltaTime { get; }

    /// <summary>The tree this node belongs to. Use sparingly — direct Tree
    /// access is escape-hatch territory and won't survive the codegen path.</summary>
    public Tree Tree { get; }

    private readonly IInputReader? _input;

    /// <summary>
    /// True if the given key was held down when input was last sampled (just
    /// before this tick). Returns false when no input service is registered.
    /// Key codes follow the GLFW convention (e.g. 87='W', 262=Right Arrow).
    /// </summary>
    public bool IsKeyDown(int key) => _input?.IsKeyDown(key) ?? false;

    internal View(Tree tree, float deltaTime, IInputReader? input)
    {
        Tree      = tree;
        DeltaTime = deltaTime;
        _input    = input;
    }
}
