using System.Runtime.CompilerServices;
using KernelEngine.Kernel.Native;

namespace KernelEngine;

/// <summary>
/// A lightweight, allocation-free result container for kernel operations.
/// Follows the "Failure as a Value" principle.
/// </summary>
public readonly struct Result(ke_result code)
{
    public ke_result Code { get; } = code;

    public bool IsOk => Code == ke_result.KE_OK;
    public bool IsError => Code != ke_result.KE_OK;

    public static implicit operator Result(ke_result code) => new(code);
    public static implicit operator ke_result(Result result) => result.Code;

    [MethodImpl(MethodImplOptions.AggressiveInlining)]
    public void ThrowIfFailed() => KernelException.ThrowIfFailed(Code);

    public override string ToString() => Code.ToString();
}

/// <summary>
/// A lightweight, allocation-free result container that holds a value or a kernel error code.
/// </summary>
public readonly struct Result<T>(ke_result code, T value = default!)
{
    public ke_result Code { get; } = code;
    private readonly T _value = value;

    public bool IsOk => Code == ke_result.KE_OK;
    public bool IsError => Code != ke_result.KE_OK;

    public T Value => IsOk ? _value : throw new KernelException(Code, "Attempted to access value of a failed Result.");

    public static implicit operator Result<T>(ke_result code) => new(code);
    public static implicit operator Result(Result<T> result) => new(result.Code);

    public override string ToString() => IsOk ? $"Ok({_value})" : $"Error({Code})";
}
