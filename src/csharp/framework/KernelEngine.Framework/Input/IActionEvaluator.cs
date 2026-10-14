using KernelEngine.Input;

namespace KernelEngine.Framework;

/// <summary>
/// The evaluation of an <see cref="IInputActionMap{TEnum}"/> without its enum type parameter.
/// </summary>
public interface IActionEvaluator
{
    /// <summary>
    /// Evaluates every action against the input once, making its held and edge state current
    /// for the tick. With a null reader, or one with no native snapshot, no key is held.
    /// </summary>
    void Evaluate(IInputReader? input);
}
