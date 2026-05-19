using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Bridges the auto-generated <see cref="ke_result"/> enum (forbidden in Abstractions because
/// it's auto-generated) to the managed <see cref="Result"/> / <see cref="KernelResult"/> types
/// at every Kernel-internal call site. Numeric values match exactly so the cast is a no-op.
/// </summary>
public static class NativeResultExtensions
{
    public static Result Wrap(this ke_result r) => (KernelResult)(int)r;

    public static Result<T> Wrap<T>(this ke_result r, T value) => new((KernelResult)(int)r, value);

    public static KernelResult ToManaged(this ke_result r) => (KernelResult)(int)r;
}
