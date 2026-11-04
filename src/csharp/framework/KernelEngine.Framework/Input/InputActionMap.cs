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
    private readonly Dictionary<int, int> _valueOfId = new();
    private readonly List<InputActionHandler> _handlers = new();

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
            if (id < 0) continue;
            map._ids[value] = id;
            map._valueOfId[id] = Convert.ToInt32(value);
        }
        return map;
    }

    /// <inheritdoc/>
    public void Evaluate(IInputReader? input)
    {
        if (input is not INativeInputReader native) throw new ArgumentException("evaluating needs a native input reader", nameof(input));
        _native.Evaluate(native.Native, _handlers.Count == 0 ? null : Dispatch);
    }

    private void Dispatch(KernelEngine.Framework.Native.InputActionEvent e)
    {
        if (!_valueOfId.TryGetValue(e.ActionId, out var value)) return;
        var evt = new ActionEvent
        {
            EnumType = typeof(TEnum),
            ActionId = value,
            Type = (ActionType)(uint)e.Type,
            Phase = (KernelEngine.Input.ActionPhase)(uint)e.Phase,
            ValueX = e.X,
            ValueY = e.Y,
            ValueZ = e.Z,
        };
        for (var i = _handlers.Count - 1; i >= 0 && !evt.Handled; i--)
            _handlers[i](ref evt);
    }

    /// <inheritdoc/>
    public void Subscribe(InputActionHandler handler) => _handlers.Add(handler);

    /// <inheritdoc/>
    public void Unsubscribe(InputActionHandler handler) => _handlers.Remove(handler);

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
