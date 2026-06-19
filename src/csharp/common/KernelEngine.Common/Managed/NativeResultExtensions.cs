using KernelEngine.Common.Native;

namespace KernelEngine;

/// <summary>
/// Bridges native result codes — both the <c>ke_result</c> enum (returned by vtable delegates)
/// and bare <c>int</c> (returned by free functions generated with ClangSharp) — to the managed
/// <see cref="Result"/> / <see cref="KernelResult"/> types. Numeric values match exactly so
/// every cast is a no-op at runtime.
/// </summary>
public static class NativeResultExtensions
{
    // ── ke_result (enum) overloads — used by vtable delegate call sites ───────

    public static Result Wrap(this ke_result r) => (KernelResult)(int)r;

    public static Result<T> Wrap<T>(this ke_result r, T value) => new((KernelResult)(int)r, value);

    public static KernelResult ToManaged(this ke_result r) => (KernelResult)(int)r;

    // ── int overloads — used by free-function P/Invoke call sites ────────────

    public static Result Wrap(this int r) => (KernelResult)r;

    public static Result<T> Wrap<T>(this int r, T value) => new((KernelResult)r, value);

    public static KernelResult ToManaged(this int r) => (KernelResult)r;
}
