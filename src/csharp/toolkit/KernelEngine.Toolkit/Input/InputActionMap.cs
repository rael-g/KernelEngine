using KernelEngine.Input;
using KernelEngine.Input.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Enum-typed adapter over the native <see cref="NativeInputActions"/> — resolves
/// each <typeparamref name="TEnum"/> value to its native action id once at load time,
/// then reads per-tick state through the native evaluator. The action-file TOML
/// grammar (<c>[action.Name]</c>, <c>bindings = [{kind=..., ...}]</c>) is parsed
/// natively; this type owns no binding data of its own.
/// </summary>
public sealed unsafe class InputActionMap<TEnum> : IInputActionMap<TEnum>, IActionEvaluator, IDisposable
    where TEnum : struct, Enum
{
    private readonly NativeInputActions _native;
    private readonly Dictionary<TEnum, int> _ids = new();

    private InputActionMap(NativeInputActions native) => _native = native;

    /// <summary>
    /// Loads bindings from the <c>.input</c> TOML file at <paramref name="path"/> and
    /// resolves every <typeparamref name="TEnum"/> value to its native action id
    /// (an enum value with no matching <c>[action.Name]</c> section reads as
    /// permanently unbound, never an error).
    /// </summary>
    public static InputActionMap<TEnum> LoadFromFile(string path)
    {
        var native = new NativeInputActions();
        native.Load(path);

        var map = new InputActionMap<TEnum>(native);
        foreach (var value in Enum.GetValues<TEnum>())
        {
            var id = native.GetActionId(value.ToString());
            if (id >= 0) map._ids[value] = id;
        }
        return map;
    }

    /// <inheritdoc/>
    public void Evaluate(IInputReader? input)
    {
        if (input is not INativeInputReader native) { _native.Evaluate(null); return; }
        var snapshot = native.Native;
        _native.Evaluate(&snapshot);
    }

    /// <inheritdoc/>
    public float GetAxis1D(TEnum action, in View view)
        => _ids.TryGetValue(action, out var id) ? _native.GetAxis1d(id) : 0f;

    /// <inheritdoc/>
    public bool IsPressed(TEnum action, in View view)
        => _ids.TryGetValue(action, out var id) && _native.IsActionDown(id);

    /// <inheritdoc/>
    public bool IsJustPressed(TEnum action, in View view)
        => _ids.TryGetValue(action, out var id) && _native.WasActionPressed(id);

    /// <inheritdoc/>
    public void Dispose() => _native.Dispose();
}
