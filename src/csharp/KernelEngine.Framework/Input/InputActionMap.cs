using System.Numerics;
using System.Runtime.CompilerServices;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Engine-internal handle the dispatcher iterates over without knowing the concrete enum type.
/// Implemented by <see cref="InputActionMap{TEnum}"/>.
/// </summary>
internal interface IInputActionMap
{
    Type EnumType { get; }

    /// <summary>
    /// Re-samples every action's bindings against the snapshot and appends every
    /// phase-transition event (Started / Performed / Canceled) to <paramref name="output"/>.
    /// </summary>
    void Evaluate(ke_input_snapshot snapshot, List<InputActionEvent> output);
}

/// <summary>
/// A typed collection of actions for the game's action enum <typeparamref name="TEnum"/>.
/// Game code declares its enum once, registers a map at startup, and from then on speaks only
/// verbs (<c>IsActionDown</c>, <c>OnInputAction</c>) — physical inputs become data.
/// </summary>
/// <typeparam name="TEnum">An <c>int</c>-backed enum. Each value is one action.</typeparam>
/// <remarks>
/// Internally backed by <c>ke_input_actions</c> from the <c>ke_framework</c> native plugin.
/// Actions added programmatically and actions loaded from <c>.input</c> files share the same
/// runtime state — both paths feed the same evaluation pipeline.
/// </remarks>
/// <example>
/// <code>
/// public enum PongAction { MoveLeft, MoveRight, Launch, Quit }
///
/// using var map = new InputActionMap&lt;PongAction&gt;();
/// map.AddAction(PongAction.MoveLeft, ActionType.Axis1D).AddWS();
/// map.AddButton(PongAction.Launch, Key.Space);
/// map.AddButton(PongAction.Quit,   Key.Escape);
/// InputActions.Register(map);
/// </code>
/// </example>
public sealed class InputActionMap<TEnum> : IInputActionMap, IDisposable where TEnum : struct, Enum
{
    private readonly NativeInputActions _native;
    private readonly Dictionary<int, int> _enumValueToActionId = new();

    Type IInputActionMap.EnumType => typeof(TEnum);

    static InputActionMap()
    {
        if (Enum.GetUnderlyingType(typeof(TEnum)) != typeof(int))
            throw new InvalidOperationException(
                $"InputActionMap<{typeof(TEnum).Name}> requires an int-backed enum.");
    }

    /// <summary>
    /// Creates an empty map. Add actions via <see cref="AddAction"/> or load them from a file
    /// via the <see cref="InputActions"/> entry points.
    /// </summary>
    public InputActionMap() : this(new MallocAllocator()) { }

    /// <summary>Creates an empty map using a caller-provided allocator (used by tests).</summary>
    public InputActionMap(Allocator allocator)
    {
        _native = new NativeInputActions(allocator) { EnumType = typeof(TEnum) };
    }

    /// <summary>
    /// Constructs a map from an already-loaded <see cref="NativeInputActions"/>. Action ids
    /// are discovered by looking up each <typeparamref name="TEnum"/> value's name in the
    /// native registry. Used by <see cref="InputActions.LoadFromProject"/>.
    /// </summary>
    internal InputActionMap(NativeInputActions native)
    {
        _native = native;
        _native.EnumType = typeof(TEnum);
        foreach (TEnum v in Enum.GetValues<TEnum>())
        {
            TEnum local = v;
            int id = _native.GetActionId(local.ToString());
            if (id >= 0) _enumValueToActionId[Unsafe.As<TEnum, int>(ref local)] = id;
        }
    }

    /// <summary>
    /// Declares an action and returns a builder for chaining bindings. Adding the same action
    /// twice throws. The action's runtime name (used by <c>.input</c> files and serialization)
    /// is the enum value's <c>ToString()</c>.
    /// </summary>
    public InputActionBuilder AddAction(TEnum action, ActionType type)
    {
        int enumValue = Unsafe.As<TEnum, int>(ref action);
        if (_enumValueToActionId.ContainsKey(enumValue))
            throw new ArgumentException($"Action {action} already registered in this map.");
        int id = _native.AddAction(action.ToString(), type);
        _enumValueToActionId[enumValue] = id;
        return new InputActionBuilder(_native, id);
    }

    /// <summary>Convenience for the common case: a Button action with one key binding.</summary>
    public InputActionBuilder AddButton(TEnum action, Key key) =>
        AddAction(action, ActionType.Button).AddBinding(key);

    /// <summary>Convenience for the common case: a Button action with one mouse-button binding.</summary>
    public InputActionBuilder AddButton(TEnum action, MouseButton button) =>
        AddAction(action, ActionType.Button).AddBinding(button);

    // ── Polling, called by the IInputActionReader<TEnum> facade ──────────────

    private int ResolveId(TEnum action)
    {
        int enumValue = Unsafe.As<TEnum, int>(ref action);
        return _enumValueToActionId.TryGetValue(enumValue, out var id) ? id : -1;
    }

    internal bool IsActionDown(TEnum action)      => ResolveId(action) is var id && id >= 0 && _native.IsActionDown(id);
    internal bool WasActionPressed(TEnum action)  => ResolveId(action) is var id && id >= 0 && _native.WasActionPressed(id);
    internal bool WasActionReleased(TEnum action) => ResolveId(action) is var id && id >= 0 && _native.WasActionReleased(id);

    internal float GetAxis1D(TEnum action)
    {
        int id = ResolveId(action);
        return id < 0 ? 0f : _native.GetAxis1D(id);
    }

    internal Vector2 GetAxis2D(TEnum action)
    {
        int id = ResolveId(action);
        if (id < 0) return Vector2.Zero;
        var (x, y) = _native.GetAxis2D(id);
        return new Vector2(x, y);
    }

    internal Vector3 GetAxis3D(TEnum action)
    {
        int id = ResolveId(action);
        if (id < 0) return Vector3.Zero;
        var (x, y, z) = _native.GetAxis3D(id);
        return new Vector3(x, y, z);
    }

    void IInputActionMap.Evaluate(ke_input_snapshot snapshot, List<InputActionEvent> output) =>
        _native.Evaluate(snapshot, output);

    public void Dispose() => _native.Dispose();
}

/// <summary>
/// Fluent helper returned by <see cref="InputActionMap{TEnum}.AddAction"/>. Multiple bindings
/// chain naturally onto a single action.
/// </summary>
public readonly struct InputActionBuilder
{
    private readonly NativeInputActions _native;
    private readonly int _actionId;

    internal InputActionBuilder(NativeInputActions native, int actionId)
    {
        _native = native;
        _actionId = actionId;
    }

    /// <summary>Button binding from a single keyboard key.</summary>
    public InputActionBuilder AddBinding(Key key)
    {
        _native.BindKey(_actionId, key);
        return this;
    }

    /// <summary>Button binding from a single mouse button.</summary>
    public InputActionBuilder AddBinding(MouseButton button)
    {
        _native.BindMouseButton(_actionId, button);
        return this;
    }

    /// <summary>
    /// Axis1D binding from a key pair: <paramref name="negative"/> emits -1,
    /// <paramref name="positive"/> emits +1; both held cancels to 0.
    /// </summary>
    public InputActionBuilder AddKeyPair(Key negative, Key positive)
    {
        _native.BindKeyPair(_actionId, negative, positive);
        return this;
    }

    /// <summary>
    /// Axis2D binding from four keys: X = right − left, Y = up − down.
    /// </summary>
    public InputActionBuilder AddKeyQuad(Key up, Key down, Key left, Key right)
    {
        _native.BindKeyQuad(_actionId, up, down, left, right);
        return this;
    }

    // ── Common composite shortcuts ───────────────────────────────────────────

    /// <summary>W/S pair → Axis1D (+1 up, −1 down).</summary>
    public InputActionBuilder AddWS()   => AddKeyPair(Key.S, Key.W);

    /// <summary>A/D pair → Axis1D (+1 right, −1 left).</summary>
    public InputActionBuilder AddAD()   => AddKeyPair(Key.A, Key.D);

    /// <summary>Up/Down arrow pair → Axis1D.</summary>
    public InputActionBuilder AddUpDown()    => AddKeyPair(Key.Down, Key.Up);

    /// <summary>Left/Right arrow pair → Axis1D.</summary>
    public InputActionBuilder AddLeftRight() => AddKeyPair(Key.Left, Key.Right);

    /// <summary>WASD → Axis2D (X = D−A, Y = W−S).</summary>
    public InputActionBuilder AddWASD()   => AddKeyQuad(Key.W, Key.S, Key.A, Key.D);

    /// <summary>Arrow keys → Axis2D.</summary>
    public InputActionBuilder AddArrows() => AddKeyQuad(Key.Up, Key.Down, Key.Left, Key.Right);
}
