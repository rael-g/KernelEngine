namespace KernelEngine.Framework;

/// <summary>
/// Read-only view of the bindings declared in an <c>.input</c> file. Action
/// values are looked up by their enum identity (not their numeric value), so
/// renaming an action requires updating the TOML — the type system catches
/// the rest.
/// </summary>
/// <remarks>
/// Methods take the current frame's <see cref="View"/> instead of holding a
/// stale snapshot reference. This keeps the map a stateless DI singleton
/// while still letting any node read the live input.
/// </remarks>
public interface IInputActionMap<TEnum> where TEnum : struct, Enum
{
    /// <summary>Sum across all bindings of axis contributions, clamped to [-1, 1].
    /// Single-key bindings contribute 0; key-pair bindings contribute
    /// <c>(positive ? +1 : 0) - (negative ? +1 : 0)</c>.</summary>
    float GetAxis1D(TEnum action, in View view);

    /// <summary>True when any single-key binding for <paramref name="action"/>
    /// is held down. Key-pair bindings count as "pressed" when the positive
    /// side is down.</summary>
    bool IsPressed(TEnum action, in View view);
}
