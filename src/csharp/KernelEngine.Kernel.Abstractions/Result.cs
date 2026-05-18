using System.Runtime.CompilerServices;

namespace KernelEngine.Kernel;

/// <summary>
/// A lightweight, allocation-free result container for kernel operations.
/// Follows the "Failure as a Value" principle.
/// </summary>
public readonly struct Result(KernelResult code)
{
    public KernelResult Code { get; } = code;

    public bool IsOk => Code == KernelResult.Ok;
    public bool IsError => Code != KernelResult.Ok;

    public static implicit operator Result(KernelResult code) => new(code);
    public static implicit operator KernelResult(Result result) => result.Code;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void ThrowIfFailed() => KernelException.ThrowIfFailed(Code);

    public override string ToString() => Code.ToString();
}

/// <summary>
/// A lightweight, allocation-free result container that holds a value or a kernel error code.
/// </summary>
public readonly struct Result<T>(KernelResult code, T value = default!)
{
    public KernelResult Code { get; } = code;
    private readonly T _value = value;

    public bool IsOk => Code == KernelResult.Ok;
    public bool IsError => Code != KernelResult.Ok;

    public T Value => IsOk
        ? _value
        : throw new KernelException(Code, "Attempted to access value of a failed Result.");

    public static implicit operator Result<T>(KernelResult code) => new(code);
    public static implicit operator Result(Result<T> result) => new(result.Code);

    public override string ToString() => IsOk ? $"Ok({_value})" : $"Error({Code})";
}
