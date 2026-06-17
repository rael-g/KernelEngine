using System.Numerics;

namespace KernelEngine.Kernel;

/// <summary>Discriminator for <see cref="InputEvent"/>.</summary>
public enum InputEventKind
{
    None             = 0,
    KeyDown          = 1,
    KeyUp            = 2,
    MouseButtonDown  = 3,
    MouseButtonUp    = 4,
    MouseScroll      = 6,
}

/// <summary>
/// One discrete input event produced on ke.main and dispatched through the node tree on ke.sim.
/// Flat layout; field meaning depends on <see cref="Kind"/>:
/// <list type="bullet">
///   <item><b>KeyDown / KeyUp</b>: <see cref="Key"/> is valid.</item>
///   <item><b>MouseButtonDown / MouseButtonUp</b>: <see cref="Button"/> is valid.</item>
///   <item><b>MouseScroll</b>: <see cref="Scroll"/> is the (dx, dy) wheel delta.</item>
/// </list>
/// <para>Mouse-cursor position is continuous state, not a discrete event. Read it via
/// <c>IInputReader.MousePosition</c>/<c>MouseDelta</c> in <c>Update</c>.</para>
/// Pass by <c>ref</c> in handlers; setting <see cref="Handled"/> (via <see cref="Consume"/>)
/// stops further propagation through the tree.
/// </summary>
public struct InputEvent
{
    public InputEventKind Kind;
    public Key            Key;
    public MouseButton    Button;
    public Vector2        Scroll;

    /// <summary>When true, the tree dispatcher stops visiting further nodes for this event.</summary>
    public bool Handled;

    /// <summary>Marks the event handled — alias for <c>Handled = true</c>.</summary>
    public void Consume() => Handled = true;
}

/// <summary>Signature for input event hooks; pass-by-ref so handlers can call <see cref="InputEvent.Consume"/>.</summary>
public delegate void InputHandler(ref InputEvent evt);

