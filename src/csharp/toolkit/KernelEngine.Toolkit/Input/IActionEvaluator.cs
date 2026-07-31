using KernelEngine.Input;

namespace KernelEngine.Framework;

/// <summary>
/// Non-generic hook the per-tick input system uses to advance an
/// <see cref="IInputActionMap{TEnum}"/>'s underlying native evaluation, without
/// depending on its enum type parameter. One <c>Evaluate</c> call per tick keeps
/// every action's held/edge state current for that tick's <c>IsPressed</c>/
/// <c>IsJustPressed</c>/<c>GetAxis1D</c> reads.
/// </summary>
public interface IActionEvaluator
{
    void Evaluate(IInputReader? input);
}
