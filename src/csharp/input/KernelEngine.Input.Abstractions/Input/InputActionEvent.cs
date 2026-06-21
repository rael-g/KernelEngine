using System.Numerics;
using System.Runtime.CompilerServices;

namespace KernelEngine.Input;

/// <summary>
/// One discrete action event, emitted by the action-layer dispatcher and propagated through the
/// node tree (<see cref="OnInputAction"/>-style handlers) in the same frame the underlying input
/// occurred.
/// </summary>
/// <remarks>
/// <para>
/// The event is non-generic so the dispatcher and Tree can carry it without leaking the game's
/// action enum type. Game code identifies its actions via the generic <see cref="Is{T}"/> /
/// <see cref="As{T}"/> helpers, which compare both the enum type and the underlying integer.
/// </para>
/// <para>
/// The value field that is meaningful depends on <see cref="Type"/>:
/// <list type="bullet">
///   <item><b>Button</b> — only <see cref="Phase"/> matters.</item>
///   <item><b>Axis1D</b> — <see cref="ValueX"/>.</item>
///   <item><b>Axis2D</b> — <see cref="ValueX"/> + <see cref="ValueY"/>.</item>
///   <item><b>Axis3D</b> — <see cref="ValueX"/> + <see cref="ValueY"/> + <see cref="ValueZ"/>.</item>
/// </list>
/// </para>
/// </remarks>
public struct InputActionEvent
{
    /// <summary>The CLR type of the action enum the event belongs to. Use <see cref="Is{T}"/> to match.</summary>
    public Type EnumType;

    /// <summary>The action's underlying integer value. Compare via <see cref="Is{T}"/>.</summary>
    public int ActionId;

    /// <summary>The action's value-shape. Decides which Value field is meaningful.</summary>
    public ActionType Type;

    /// <summary>Lifecycle phase (Started / Performed / Canceled).</summary>
    public ActionPhase Phase;

    /// <summary>Axis1D / Axis2D / Axis3D X component.</summary>
    public float ValueX;
    /// <summary>Axis2D / Axis3D Y component.</summary>
    public float ValueY;
    /// <summary>Axis3D Z component.</summary>
    public float ValueZ;

    /// <summary>True when a handler has called <see cref="Consume"/>; the dispatcher stops further propagation.</summary>
    public bool Handled;

    /// <summary>Marks the event handled — alias for <c>Handled = true</c>.</summary>
    public void Consume() => Handled = true;

    /// <summary>Value as <see cref="Vector2"/> (use for Axis2D).</summary>
    public Vector2 Vector2Value
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => new(ValueX, ValueY);
    }

    /// <summary>Value as <see cref="Vector3"/> (use for Axis3D).</summary>
    public Vector3 Vector3Value
    {
        [MethodImpl(MethodImplOptions.AggressiveInlining)]
        get => new(ValueX, ValueY, ValueZ);
    }

    /// <summary>
    /// True when this event matches <paramref name="action"/> in both enum type and value.
    /// Zero-allocation — does not box the enum.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool Is<T>(T action) where T : struct, Enum =>
        EnumType == typeof(T) && ActionId == Unsafe.As<T, int>(ref action);

    /// <summary>
    /// Tries to read the action as a typed enum value. Returns true and writes <paramref name="action"/>
    /// when the event belongs to <typeparamref name="T"/>; otherwise returns false.
    /// </summary>
    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public bool As<T>(out T action) where T : struct, Enum
    {
        if (EnumType == typeof(T))
        {
            int id = ActionId;
            action = Unsafe.As<int, T>(ref id);
            return true;
        }
        action = default;
        return false;
    }
}

/// <summary>Signature for action event hooks; <c>ref</c> so handlers can <see cref="InputActionEvent.Consume"/>.</summary>
public delegate void InputActionHandler(ref InputActionEvent evt);
