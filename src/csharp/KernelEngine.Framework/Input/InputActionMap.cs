using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Engine-internal handle the dispatcher iterates over without knowing the concrete enum type.
/// Implemented by <see cref="InputActionMap{TEnum}"/>.
/// </summary>
internal interface IInputActionMap
{
    Type EnumType { get; }
    IReadOnlyList<InputAction> Actions { get; }
}

/// <summary>
/// A typed collection of actions for the game's action enum <typeparamref name="TEnum"/>.
/// Game code declares its enum once, registers a map at startup, and from then on speaks only
/// verbs (<c>IsActionDown</c>, <c>OnInputAction</c>) — physical inputs become data.
/// </summary>
/// <typeparam name="TEnum">An <c>int</c>-backed enum. Each value is one action.</typeparam>
/// <example>
/// <code>
/// public enum PongAction { MoveLeft, MoveRight, Launch, Quit }
///
/// var map = new InputActionMap&lt;PongAction&gt;();
/// map.AddAction(PongAction.MoveLeft,  ActionType.Axis1D).AddBinding(Vector1Composite.WS());
/// map.AddAction(PongAction.Launch,    ActionType.Button).AddBinding(Key.Space);
/// map.AddAction(PongAction.Quit,      ActionType.Button).AddBinding(Key.Escape);
/// InputActions.Register(map);
/// </code>
/// </example>
public sealed class InputActionMap<TEnum> : IInputActionMap where TEnum : struct, Enum
{
    private readonly Dictionary<int, InputAction> _actions = new();

    Type IInputActionMap.EnumType => typeof(TEnum);
    IReadOnlyList<InputAction> IInputActionMap.Actions => _actionsList;
    private readonly List<InputAction> _actionsList = new();

    static InputActionMap()
    {
        // Validate underlying type once. We rely on Unsafe.As&lt;TEnum,int&gt; reads.
        if (Enum.GetUnderlyingType(typeof(TEnum)) != typeof(int))
            throw new InvalidOperationException(
                $"InputActionMap<{typeof(TEnum).Name}> requires an int-backed enum.");
    }

    /// <summary>
    /// Declares an action and returns a builder for chaining bindings.
    /// Adding the same action twice throws.
    /// </summary>
    public InputActionBuilder AddAction(TEnum action, ActionType type)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        if (_actions.ContainsKey(id))
            throw new ArgumentException($"Action {action} already registered in this map.");
        var entry = new InputAction { ActionId = id, Type = type };
        _actions[id] = entry;
        _actionsList.Add(entry);
        return new InputActionBuilder(entry);
    }

    /// <summary>Convenience for the common case: a <see cref="ActionType.Button"/> action with one key binding.</summary>
    public InputActionBuilder AddButton(TEnum action, Key key) =>
        AddAction(action, ActionType.Button).AddBinding(key);

    /// <summary>Convenience for the common case: an <see cref="ActionType.Button"/> action with one mouse-button binding.</summary>
    public InputActionBuilder AddButton(TEnum action, MouseButton button) =>
        AddAction(action, ActionType.Button).AddBinding(button);

    // ── Polling, called by the IInputActionReader<TEnum> facade ──────────────

    internal bool IsActionDown(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) && a.IsActiveNow;
    }

    internal bool WasActionPressed(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) && a.IsActiveNow && !a.WasActivePrev;
    }

    internal bool WasActionReleased(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) && !a.IsActiveNow && a.WasActivePrev;
    }

    internal float GetAxis1D(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) ? a.CurrX : 0f;
    }

    internal Vector2 GetAxis2D(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) ? new Vector2(a.CurrX, a.CurrY) : Vector2.Zero;
    }

    internal Vector3 GetAxis3D(TEnum action)
    {
        int id = Unsafe.As<TEnum, int>(ref action);
        return _actions.TryGetValue(id, out var a) ? new Vector3(a.CurrX, a.CurrY, a.CurrZ) : Vector3.Zero;
    }
}
