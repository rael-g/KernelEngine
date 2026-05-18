namespace KernelEngine.Kernel;

/// <summary>
/// Managed mirror of the kernel's native result code (<c>ke_result</c>).
/// Numeric values match exactly so the concrete Kernel can cross-cast at the boundary.
/// </summary>
public enum KernelResult
{
    Ok = 0,
    Error = 1,
    OutOfMemory = 2,
    InvalidArgument = 3,
    NotFound = 4,
    AlreadyExists = 5,
    NotInitialized = 6,
    NotSupported = 7,
    Io = 100,
    Window = 200,
    Render = 300,
    GpuFatal = 301,
}
