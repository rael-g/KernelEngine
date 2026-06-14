namespace KernelEngine.Framework;

/// <summary>
/// Provides per-action queries over a set of input bindings loaded from a
/// TOML <c>.input</c> file. Backed by <see cref="InputActionMap{TEnum}"/>.
/// </summary>
public interface IInputActionMap<TEnum> where TEnum : struct, Enum
{
    /// <summary>
    /// Returns a value in [-1, 1] by summing all key-pair bindings for the action.
    /// </summary>
    float GetAxis1D(TEnum action, in View view);

    /// <summary>
    /// Returns true if any binding for the action has its positive key held.
    /// </summary>
    bool IsPressed(TEnum action, in View view);
}
