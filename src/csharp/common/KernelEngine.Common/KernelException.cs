namespace KernelEngine.Kernel;

/// <summary>
/// Thrown when a kernel operation returns a non-OK result.
/// </summary>
public sealed class KernelException : Exception
{
    /// <summary>The result code that caused this exception.</summary>
    public KernelResult Result { get; }

    public KernelException(KernelResult result, string? context = null, string? message = null)
        : base(message ?? FormatMessage(result, context))
    {
        Result = result;
    }

    private static string FormatMessage(KernelResult result, string? context) =>
        string.IsNullOrEmpty(context) ? $"Kernel error: {result}" : $"{result} in {context}";

    public static void ThrowIfFailed(KernelResult result, string context = "")
    {
        if (result != KernelResult.Ok)
            throw new KernelException(result, context);
    }
}
