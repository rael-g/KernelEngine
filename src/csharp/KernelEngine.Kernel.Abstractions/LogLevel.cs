namespace KernelEngine.Kernel;

/// <summary>
/// Severity level for log events. Mirrors the kernel's native enum
/// (<c>ke_log_level</c>) but is pure managed — Abstractions never reference
/// auto-generated native types.
/// </summary>
public enum LogLevel
{
    Trace = 0,
    Debug = 1,
    Info = 2,
    Warning = 3,
    Error = 4,
    Critical = 5,
}
