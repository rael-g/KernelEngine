namespace KernelEngine.Kernel.Native;

/// <summary>
/// Two-value result enum mirroring the C <c>ke_result</c>.
/// Rich error context is carried by <c>ke_error</c> on the native side;
/// C# callers currently pass <c>null</c> for <c>out_error</c> and receive
/// <see cref="KernelException"/> on failure.
/// </summary>
public enum ke_result
{
    KE_OK = 0,
    KE_ERROR = -1,
}
