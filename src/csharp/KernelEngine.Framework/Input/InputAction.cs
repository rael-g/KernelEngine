using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Runtime state of a single registered action — its declared type, bindings, and the value
/// computed for the current frame. Owned by <see cref="InputActionMap{TEnum}"/>; game code never
/// constructs these directly (use <c>map.AddAction(action, type).AddBinding(...)</c>).
/// </summary>
internal sealed class InputAction
{
    public int        ActionId;
    public ActionType Type;
    public readonly List<InputBinding> Bindings = new(2);

    // Frame state — written by the dispatcher, read by the polling reader.
    public float PrevX, PrevY, PrevZ;
    public float CurrX, CurrY, CurrZ;

    public bool IsActiveNow =>
        Type == ActionType.Button
            ? CurrX > 0.5f
            : (CurrX != 0f || CurrY != 0f || CurrZ != 0f);

    public bool WasActivePrev =>
        Type == ActionType.Button
            ? PrevX > 0.5f
            : (PrevX != 0f || PrevY != 0f || PrevZ != 0f);
}

/// <summary>
/// Fluent helper returned by <see cref="InputActionMap{TEnum}.AddAction"/> so multiple bindings
/// chain naturally: <c>map.AddAction(GameAction.Move, ActionType.Axis2D).AddBinding(Vector2Composite.WASD())</c>.
/// </summary>
public readonly struct InputActionBuilder
{
    private readonly InputAction _action;
    internal InputActionBuilder(InputAction action) { _action = action; }

    /// <summary>Adds a binding to the action being built. Type must match the action's <see cref="ActionType"/>.</summary>
    public InputActionBuilder AddBinding(InputBinding binding)
    {
        if (binding.Type != _action.Type)
            throw new ArgumentException(
                $"Binding type ({binding.Type}) does not match action type ({_action.Type}).");
        _action.Bindings.Add(binding);
        return this;
    }

    /// <summary>Convenience: button binding from a single key.</summary>
    public InputActionBuilder AddBinding(Key key) => AddBinding(new KeyBinding(key));

    /// <summary>Convenience: button binding from a single mouse button.</summary>
    public InputActionBuilder AddBinding(MouseButton button) => AddBinding(new MouseButtonBinding(button));
}
