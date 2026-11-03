using KernelEngine.Input;
using KernelEngine.Input.Native;

namespace KernelEngine.Framework;

/// <summary>
/// Enum-typed adapter over <see cref="InputActions"/>. Each <typeparamref name="TEnum"/>
/// value is resolved once, at load, to the native action named like the value; a value with
/// no such action reads as unbound. The file is parsed natively and this type owns no binding
/// data. Disposing it destroys the native actions.
/// </summary>
public sealed unsafe class InputActionMap<TEnum> : IInputActionMap<TEnum>, IActionEvaluator, IDisposable
    where TEnum : struct, Enum
{
    private readonly InputActions _native;
    private readonly Dictionary<TEnum, int> _ids = new();

    private InputActionMap(InputActions native) => _native = native;

    /// <summary>
    /// Loads bindings from the <c>.input</c> TOML file at <paramref name="path"/>, read through
    /// <paramref name="io"/>, and resolves every <typeparamref name="TEnum"/> value to its native
    /// action id.
    /// </summary>
    /// <exception cref="InvalidOperationException">The native load fails.</exception>
    public static InputActionMap<TEnum> LoadFromFile(KernelEngine.Io.INativeIo io, string path)
    {
        var native = new InputActions(io);
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
        if (input is not INativeInputReader native) throw new ArgumentException("evaluating needs a native input reader", nameof(input));
        _native.Evaluate(native.Native, null);
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
