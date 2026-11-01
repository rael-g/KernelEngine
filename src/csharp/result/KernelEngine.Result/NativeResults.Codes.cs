#nullable enable

namespace KernelEngine;

/// <summary>
/// Turns the result code a native call returned into the exception that stands for it. The detail
/// of a failure is in the failing library's log, never in the code, so the message names the call
/// and the code only.
/// </summary>
public static class NativeResults
{
    /// <summary>Throws the exception for <paramref name="code"/> when it is not <c>KE_OK</c>.</summary>
    /// <param name="code">What the call returned.</param>
    /// <param name="context">The name of the call, prefixed to the message.</param>
    public static void ThrowIfFailed(KernelEngine.Result.Native.Result code, string context)
    {
        if (code != KernelEngine.Result.Native.Result.Ok)
            throw FromCode(code, context);
    }

    /// <summary>The exception that stands for a code other than <c>KE_OK</c>.</summary>
    /// <param name="code">What the call returned.</param>
    /// <param name="context">The name of the call, prefixed to the message.</param>
    public static Exception FromCode(KernelEngine.Result.Native.Result code, string context) =>
        Create(code, $"{context} failed with {Name(code)}; the library's log holds the detail");

    static string Name(KernelEngine.Result.Native.Result code) =>
        Enum.IsDefined(code) ? code.ToString() : $"result code 0x{(uint)code:x8}";

    static Exception Create(KernelEngine.Result.Native.Result code, string message) => code switch
    {
        KernelEngine.Result.Native.Result.NotFound => new KeyNotFoundException(message),
        KernelEngine.Result.Native.Result.Io => new IOException(message),
        KernelEngine.Result.Native.Result.OutOfMemory => new OutOfMemoryException(message),
        KernelEngine.Result.Native.Result.InvalidArgument => new ArgumentException(message),
        KernelEngine.Result.Native.Result.NotInitialized => new InvalidOperationException(message),
        KernelEngine.Result.Native.Result.NotSupported => new NotSupportedException(message),
        KernelEngine.Result.Native.Result.AlreadyExists => new InvalidOperationException(message),
        _ => new InvalidOperationException(message),
    };

    /// <summary>
    /// The code that stands for <paramref name="exception"/>: the first code whose exception
    /// type it is exactly, or the general code.
    /// </summary>
    /// <param name="exception">What a managed handler threw.</param>
    public static KernelEngine.Result.Native.Result ToCode(Exception exception) => exception.GetType().Name switch
    {
        "KeyNotFoundException" => KernelEngine.Result.Native.Result.NotFound,
        "IOException" => KernelEngine.Result.Native.Result.Io,
        "OutOfMemoryException" => KernelEngine.Result.Native.Result.OutOfMemory,
        "ArgumentException" => KernelEngine.Result.Native.Result.InvalidArgument,
        "NotSupportedException" => KernelEngine.Result.Native.Result.NotSupported,
        _ => KernelEngine.Result.Native.Result.General,
    };
}
