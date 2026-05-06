using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Thrown when a native kernel operation returns a non-OK result.
/// </summary>
public sealed class KernelException : Exception
{
    private static readonly Dictionary<ke_result, string> ResultNames = new()
    {
        { ke_result.KE_OK, "KE_OK" },
        { ke_result.KE_ERROR, "KE_ERROR" },
        { ke_result.KE_ERROR_OUT_OF_MEMORY, "KE_ERROR_OUT_OF_MEMORY" },
        { ke_result.KE_ERROR_INVALID_ARGUMENT, "KE_ERROR_INVALID_ARGUMENT" },
        { ke_result.KE_ERROR_NOT_FOUND, "KE_ERROR_NOT_FOUND" },
        { ke_result.KE_ERROR_ALREADY_EXISTS, "KE_ERROR_ALREADY_EXISTS" },
        { ke_result.KE_ERROR_NOT_INITIALIZED, "KE_ERROR_NOT_INITIALIZED" },
        { ke_result.KE_ERROR_NOT_SUPPORTED, "KE_ERROR_NOT_SUPPORTED" },
        { ke_result.KE_ERROR_IO, "KE_ERROR_IO" },
        { ke_result.KE_ERROR_WINDOW, "KE_ERROR_WINDOW" },
        { ke_result.KE_ERROR_RENDER, "KE_ERROR_RENDER" },
        { ke_result.KE_ERROR_GPU_FATAL, "KE_ERROR_GPU_FATAL" },
    };

    /// <summary>The native result code that caused this exception.</summary>
    public ke_result Result { get; }

    public KernelException(ke_result result, string? context = null, string? message = null)
        : base(message ?? FormatMessage(result, context))
    {
        Result = result;
    }

    private static string FormatMessage(ke_result result, string? context)
    {
        string name = ResultNames.TryGetValue(result, out var n) ? n : $"UNKNOWN_ERROR({(int)result})";
        return string.IsNullOrEmpty(context) ? $"Kernel error: {name}" : $"{name} in {context}";
    }

    public static void ThrowIfFailed(ke_result result, string context = "")
    {
        if (result != ke_result.KE_OK)
            throw new KernelException(result, context);
    }
}
