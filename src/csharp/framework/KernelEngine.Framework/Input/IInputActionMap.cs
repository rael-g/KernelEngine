using KernelEngine.Input;
namespace KernelEngine.Framework;

/// <summary>
/// Per-action queries over a set of input bindings loaded from a TOML <c>.input</c> file.
/// </summary>
public interface IInputActionMap<TEnum> where TEnum : struct, Enum
{
    /// <summary>
    /// Returns the action's value in [-1, 1]: of all its bindings, the one with the largest
    /// magnitude. Zero for an action the file does not bind.
    /// </summary>
    float GetAxis1D(TEnum action);

    /// <summary>
    /// Returns true while the action is active, which is while any of its bindings gives a
    /// non-zero value. False for an action the file does not bind.
    /// </summary>
    bool IsPressed(TEnum action);

    /// <summary>
    /// Returns true on the evaluation in which the action became active and was not active on
    /// the one before. False for an action the file does not bind.
    /// </summary>
    bool IsJustPressed(TEnum action);

    /// <summary>
    /// Adds <paramref name="handler"/> to the handlers each phase transition of an action is
    /// handed to. The handler added last hears an event first, and an event a handler consumes
    /// reaches no handler added before it.
    /// </summary>
    void Subscribe(InputActionHandler handler);

    /// <summary>Removes <paramref name="handler"/>; a handler never added is ignored.</summary>
    void Unsubscribe(InputActionHandler handler);
}
