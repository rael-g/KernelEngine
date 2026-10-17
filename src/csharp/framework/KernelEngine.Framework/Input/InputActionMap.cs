using KernelEngine.Input;
using KernelEngine.Input.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Enum-typed adapter over <see cref="NativeInputActions"/>. Each <typeparamref name="TEnum"/>
/// value is resolved once, at load, to the native action named like the value; a value with
/// no such action reads as unbound. The file is parsed natively and this type owns no binding
/// data. Disposing it destroys the native actions.
/// </summary>
public sealed unsafe class InputActionMap<TEnum> : IInputActionMap<TEnum>, IActionEvaluator, IDisposable
    where TEnum : struct, Enum
{
    private readonly NativeInputActions _native;
    private readonly Dictionary<TEnum, int> _ids = new();

    private InputActionMap(NativeInputActions native) => _native = native;

    /// <summary>
    /// Loads bindings from the <c>.input</c> TOML file at <paramref name="path"/> and resolves
    /// every <typeparamref name="TEnum"/> value to its native action id.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native load fails.</exception>
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
        if (input is not INativeInputReader native) { _native.Evaluate(null, null); return; }
        var snapshot = native.Native;
        _native.Evaluate(&snapshot, null);
    }

    /// <inheritdoc/>
    public float GetAxis1D(TEnum action)
        => _ids.TryGetValue(action, out var id) ? _native.GetAxis1d(id) : 0f;

    /// <inheritdoc/>
    public bool IsPressed(TEnum action)
        => _ids.TryGetValue(action, out var id) && _native.IsActionDown(id);

    /// <inheritdoc/>
    public bool IsJustPressed(TEnum action)
        => _ids.TryGetValue(action, out var id) && _native.WasActionPressed(id);

    /// <inheritdoc/>
    public void Dispose() => _native.Dispose();
}
