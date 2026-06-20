using System.Runtime.InteropServices;
using KernelEngine.Common.Native;

namespace KernelEngine;

/// <summary>
/// Managed snapshot of a native <c>ke_error</c>. Copies the entire error — type (with its
/// parent chain), message, source location, and cause chain — into managed memory at the
/// boundary, holding no native pointer. Safe to throw, catch, log, and outlive the native call.
/// </summary>
public sealed class KernelError : Exception
{
    /// <summary>The error's type node, or <see langword="null"/> if the native error carried none.</summary>
    public KernelErrorType? Type { get; }

    /// <summary>Source file where the native error was raised (<c>__FILE__</c>), if available.</summary>
    public string? NativeFile { get; }

    /// <summary>Source line where the native error was raised (<c>__LINE__</c>), or 0 if unknown.</summary>
    public uint NativeLine { get; }

    /// <summary>The underlying error this one wraps, or <see langword="null"/> at the chain's end.</summary>
    public KernelError? Cause { get; }

    private KernelError(KernelErrorType? type, string message, string? file, uint line, KernelError? cause)
        : base(message)
    {
        Type = type;
        NativeFile = file;
        NativeLine = line;
        Cause = cause;
    }

    /// <summary>
    /// True if this error's type is named <paramref name="typeName"/> or descends from it.
    /// Convenience over <c>Type?.Is(typeName)</c>.
    /// </summary>
    public bool Is(string typeName) => Type?.Is(typeName) ?? false;

    /// <summary>
    /// Materializes a managed <see cref="KernelError"/> from a native <c>ke_error*</c>.
    /// Boundary helper called inside wrappers; the result holds no native pointer, so it's
    /// safe to surface to game code. Public only because cross-assembly wrappers need it
    /// (no <c>InternalsVisibleTo</c>) — game code never calls it, only catches the result.
    /// </summary>
    public static unsafe KernelError FromNative(ke_error* error, string? context = null)
    {
        if (error is null)
            return new KernelError(null, Prefix(context, "native call failed without error detail"), null, 0, null);

        KernelErrorType? type = KernelErrorType.FromNative(error->type);
        string message = error->message is not null
            ? Marshal.PtrToStringUTF8((nint)error->message) ?? ""
            : type?.Name ?? "native error";
        message = Prefix(context, message);
        string? file = error->file is not null ? Marshal.PtrToStringUTF8((nint)error->file) : null;
        KernelError? cause = error->cause is not null ? FromNative(error->cause) : null;

        return new KernelError(type, message, file, error->line, cause);
    }

    /// <summary>
    /// Throws a <see cref="KernelError"/> built from <paramref name="error"/> when
    /// <paramref name="ok"/> is <see langword="false"/>. The canonical wrapper failure check
    /// for the native "<c>bool</c> + <c>out_error</c>" calling convention.
    /// </summary>
    public static unsafe void ThrowIfFailed(bool ok, ke_error* error, string? context = null)
    {
        if (!ok)
            throw FromNative(error, context);
    }

    private static string Prefix(string? context, string message) =>
        string.IsNullOrEmpty(context) ? message : $"{context}: {message}";
}
