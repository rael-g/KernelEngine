using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

/// <summary>
/// Thrown when a native kernel operation returns a non-OK result.
/// </summary>
public sealed class KernelException(ke_result result, string? message = null)
    : Exception(message ?? $"Kernel error: {result}")
{
    /// <summary>The native result code that caused this exception.</summary>
    public ke_result Result { get; } = result;

    public static void ThrowIfFailed(ke_result result)
    {
        if (result != ke_result.KE_OK)
            throw new KernelException(result);
    }
}
