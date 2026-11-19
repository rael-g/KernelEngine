using NativeResult = KernelEngine.Result.Native.Result;

namespace KernelEngine;

/// <summary>Turns the result of a native call the SDK makes directly into the exception the generated classes throw for the same code.</summary>
static class NativeCall
{
    /// <summary>Throws the exception <c>resultExceptions</c> in <c>scripts/api_domains.json</c> names for <paramref name="code"/> unless it is <see cref="NativeResult.Ok"/>.</summary>
    public static void ThrowIfFailed(NativeResult code, string call)
    {
        if (code == NativeResult.Ok) return;
        var message = $"{call} failed with {code}";
        throw code switch
        {
            NativeResult.NotFound => new KeyNotFoundException(message),
            NativeResult.Io => new IOException(message),
            NativeResult.OutOfMemory => new OutOfMemoryException(message),
            NativeResult.InvalidArgument => new ArgumentException(message),
            NativeResult.NotSupported => new NotSupportedException(message),
            NativeResult.Cancelled => new OperationCanceledException(message),
            _ => new InvalidOperationException(message),
        };
    }
}
